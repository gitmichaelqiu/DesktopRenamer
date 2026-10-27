import SwiftUI
import AVKit

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
    @State private var spaceAPIAccessController: SpaceAPIAccessController?
    @State private var isSpaceAPIEnabled = false
    
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
                
                Text("DesktopRenamer needs these permissions to manage windows and Spaces.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 40)
            }

            if isSpaceAPIEnabled, let spaceAPIAccessController {
                SpaceAPIAccessOnboardingSection(accessController: spaceAPIAccessController)
                    .frame(maxWidth: 460)
            }
            
            VStack(spacing: 10) {
                permissionButton(
                    title: "Accessibility",
                    isGranted: permissionManager.hasAccessibilityPermission,
                    action: permissionManager.requestAccessibilityPermission
                )
                permissionButton(
                    title: "Screen Recording",
                    isGranted: permissionManager.isScreenCaptureGranted,
                    action: permissionManager.requestScreenCapturePermission
                )
            }
        }
        .padding()
        .onAppear {
            permissionManager.refresh()
        }
        .task {
            while !Task.isCancelled {
                if let spaceManager = AppDelegate.shared?.spaceManager {
                    isSpaceAPIEnabled = SpaceManager.isAPIEnabled
                    spaceAPIAccessController = spaceManager.spaceAPI?.accessController
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func permissionButton(
        title: LocalizedStringKey,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isGranted ? .green : .white)
                Text(title)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(isGranted ? Color.blue : Color.red)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct SpaceAPIAccessOnboardingSection: View {
    @ObservedObject var accessController: SpaceAPIAccessController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SpaceAPI Access")
                .font(.headline)

            Toggle(
                "Allow only approved apps",
                isOn: Binding(
                    get: { accessController.isRestrictedForSettings },
                    set: { value in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            accessController.setRestricted(value)
                        }
                    }
                )
            )
            .toggleStyle(.switch)

            Text("This setting controls both SpaceAPI and AppleScript access.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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
