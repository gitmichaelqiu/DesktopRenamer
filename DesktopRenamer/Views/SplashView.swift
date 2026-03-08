import SwiftUI

struct SplashView: View {
    @Environment(\.openURL) var openURL
    var onClose: () -> Void
    
    @State private var currentPage = 0
    private let totalPages = 4

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            ZStack {
                switch currentPage {
                case 0:
                    WelcomePage()
                        .transition(pageTransition)
                case 1:
                    NamingFeaturePage()
                        .transition(pageTransition)
                case 2:
                    HotkeyFeaturePage()
                        .transition(pageTransition)
                case 3:
                    RaycastFeaturePage(openURL: openURL)
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

struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
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

struct NamingFeaturePage: View {
    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [.blue, .cyan]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                    .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                Text("Name Your Spaces")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                Text("Stop guessing what's on 'Desktop 4'.\nAssign persistent, custom names to all your spaces so you always know where you are.")
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

struct HotkeyFeaturePage: View {
    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [.green, .mint]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                    .shadow(color: .green.opacity(0.3), radius: 15, x: 0, y: 8)
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                Text("Global Hotkeys")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                Text("Switch between spaces instantly. Move windows around seamlessly.\nAll custom bindable and without touching your mouse.")
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
