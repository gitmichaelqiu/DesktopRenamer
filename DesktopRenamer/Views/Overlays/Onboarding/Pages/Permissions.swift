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
                
                Text("DesktopRenamer requires Accessibility and Screen Recording permissions for hotkeys, trackpad overrides, and window movement to function correctly.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 40)
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
