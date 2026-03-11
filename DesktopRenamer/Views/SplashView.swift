import SwiftUI

struct SplashView: View {
    @Environment(\.openURL) var openURL
    var onClose: () -> Void
    
    @State private var currentPage = 0
    private let totalPages = 6

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            ZStack {
                switch currentPage {
                case 0:
                    WelcomePage()
                        .transition(pageTransition)
                case 1:
                    NameAndLabelsPage()
                        .transition(pageTransition)
                case 2:
                    MenuBarPage()
                        .transition(pageTransition)
                case 3:
                    ShortcutsAndGesturesPage()
                        .transition(pageTransition)
                case 4:
                    RaycastFeaturePage(openURL: openURL)
                        .transition(pageTransition)
                case 5:
                    PermissionsAndMorePage()
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
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .frame(width: 550, height: 450)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// MARK: - Pages

struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Image("AppIcon")
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
            
            VStack(spacing: 8) {
                Text("Welcome to\nDesktopRenamer")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                
                Text("Take back control of your macOS spaces.")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct NameAndLabelsPage: View {
    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [.blue, .cyan]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                    .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)
                Image(systemName: "tag.fill")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                Text("Name & Labels")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                Text("Assign persistent, custom names to all your spaces. DesktopRenamer displays these beautifully as large labels in Mission Control and discreet active labels when you switch spaces.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

struct MenuBarPage: View {
    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [.orange, .yellow]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                    .shadow(color: .orange.opacity(0.3), radius: 15, x: 0, y: 8)
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                Text("Menu Bar & Option-Click")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                Text("Quickly switch spaces directly from the menu bar.\n\nHere's a pro-tip: Hold the **Option (⌥)** key in the menu to instantly move your active window to the selected space!")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

struct ShortcutsAndGesturesPage: View {
    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [.green, .mint]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                    .shadow(color: .green.opacity(0.3), radius: 15, x: 0, y: 8)
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                Text("Hotkeys & Trackpad")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                Text("Bind global hotkeys to switch spaces or move windows immediately.\n\nHate macOS animation lag? Enable **Trackpad Switch Override** for instant, zero-delay swipe switching using 3 or 4 fingers.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

struct RaycastFeaturePage: View {
    var openURL: OpenURLAction

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [.purple, .indigo]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                    .shadow(color: .purple.opacity(0.3), radius: 15, x: 0, y: 8)
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                Text("Raycast Integration")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                Text("Are you a power user? Integrate directly with Raycast to manage and switch spaces elegantly via your favorite launcher.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }
            .padding(.horizontal, 40)

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
                    LinearGradient(gradient: Gradient(colors: [Color.purple, Color.blue]), startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 8)
        }
        .padding()
    }
}

struct PermissionsAndMorePage: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [.red, .orange]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 90, height: 90)
                    .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                Text("Permissions & More Apps")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                
                Text("DesktopRenamer requires Accessibility and Automation permissions for hotkeys and trackpad overrides. Enable them in Settings → Permissions.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
            }
            
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
