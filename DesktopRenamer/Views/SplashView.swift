import SwiftUI
import AVKit

struct SplashView: View {
    @Environment(\.openURL) var openURL
    var onClose: () -> Void
    
    @State private var currentPage = 0
    @State private var movingForward = true
    private let totalPages = 8

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
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
                    RaycastFeaturePage(openURL: openURL)
                        .transition(pageTransition)
                case 6:
                    PermissionsPage()
                        .transition(pageTransition)
                case 7:
                    MoreAppsPage()
                        .transition(pageTransition)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom navigation bar
            HStack {
                // Page indicator dots
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Capsule()
                            .fill(currentPage == index ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: currentPage == index ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                    }
                }
                
                Spacer()
                
                // Back Button
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
                
                // Next / Get Started Button
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

// MARK: - Auto Playing Video View
struct AutoPlayingVideoView: NSViewRepresentable {
    let videoName: String
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspectFill
        
        // Attempt to find the video file in the bundle
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            let player = AVPlayer(url: url)
            playerView.player = player
            player.actionAtItemEnd = .none // Setup for looping
            
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                player.seek(to: .zero)
                player.play()
            }
            
            player.play()
        }
        
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Handle updates if needed
    }
}

// MARK: - Reusable Page Templates

struct SingleVideoFeaturePage: View {
    let title: String
    let subtitle: String
    let videoName: String
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
            }
            
            AutoPlayingVideoView(videoName: videoName)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
        .padding(.top, 30)
    }
}

struct DoubleVideoFeaturePage: View {
    let title: String
    let subtitle: String
    let videoName1: String
    let videoName2: String
    let label1: String
    let label2: String
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
            }
            
            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(label1)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    AutoPlayingVideoView(videoName: videoName1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                }
                
                VStack(spacing: 8) {
                    Text(label2)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    GeometryReader { geo in
                        if videoName2 == "ActiveLabel" {
                            let targetWidth = max(geo.size.width, geo.size.height * (1736.0 / 1080.0))
                            AutoPlayingVideoView(videoName: videoName2)
                                .frame(width: targetWidth, height: geo.size.height)
                                .position(x: geo.size.width - targetWidth / 2, y: geo.size.height / 2)
                        } else {
                            AutoPlayingVideoView(videoName: videoName2)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .padding(.top, 30)
    }
}

// MARK: - Pages

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
            
            VStack(spacing: 8) {
                Text("Welcome to\nDesktopRenamer")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                
                Text("Take back control of your macOS spaces.")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
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
    @AppStorage("kShowActiveLabels") private var showActiveLabels = true

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
            
            HStack(spacing: 40) {
                Toggle("Show preview labels", isOn: $showPreviewLabels)
                    .toggleStyle(.switch)
                Toggle("Show active space labels", isOn: $showActiveLabels)
                    .toggleStyle(.switch)
            }
            .padding(.bottom, 20)
        }
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
            
            Toggle("Enable switch gesture override", isOn: $gestureEnabled)
                .toggleStyle(.switch)
                .padding(.bottom, 20)
        }
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
            
            // Raycast Image Display
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
                // Fallback icon if image cannot be found
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
                
                Text("DesktopRenamer requires Accessibility and Automation permissions for hotkeys and trackpad overrides to function correctly.\n\nPlease enable them in System Settings → Privacy & Security.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 40)
            }
            
            HStack(spacing: 20) {
                // Accessibility Button
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
                    .background(permissionManager.isAccessibilityGranted ? Color.secondary.opacity(0.5) : Color.red)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Automation Button
                Button(action: {
                    permissionManager.requestAutomationPermission()
                }) {
                    HStack {
                        Image(systemName: permissionManager.isAutomationGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(permissionManager.isAutomationGranted ? .green : .white)
                        Text("Automation")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(permissionManager.isAutomationGranted ? Color.secondary.opacity(0.5) : Color.red)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
    }
}

struct MoreAppsPage: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Discover More Apps")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                Text("Check out these other productivity tools we've built.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 10)
            
            HStack(alignment: .top, spacing: 20) {
                // OptClicker
                OtherAppCard(
                    imageName: "OptClickerIcon_Default",
                    appName: "OptClicker",
                    description: NSLocalizedString("Let you right-click with the Option key.", comment: ""),
                    url: "https://github.com/gitmichaelqiu/OptClicker"
                )
                
                // SpaceSwitcher
                OtherAppCard(
                    imageName: "SpaceSwitcherIcon_Default",
                    appName: "SpaceSwitcher",
                    description: NSLocalizedString("Control which app and dock to show in each space.", comment: ""),
                    url: "https://github.com/gitmichaelqiu/SpaceSwitcher"
                )
            }
            .padding(.top, 4)
        }
        .padding()
    }
}


