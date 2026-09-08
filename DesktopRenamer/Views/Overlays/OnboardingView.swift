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
