import SwiftUI

struct AboutView: View {
    var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "DesktopRenamer"
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var currentYear: String {
        let year = Calendar.current.component(.year, from: Date())
        return String(year)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - App Header
                VStack(spacing: 12) {
                    if let nsImage = NSApplication.shared.applicationIconImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120, height: 120)
                            .shadow(radius: 5)
                    }

                    VStack(spacing: 4) {
                        Text(appName)
                            .font(.system(size: 28, weight: .bold))

                        Text("v\(appVersion)")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 20)

                Text(NSLocalizedString("Settings.About.Description", comment: "Description"))
                    .multilineTextAlignment(.center)
                    .font(.body)
                    .lineSpacing(4)
                    .padding(.horizontal, 30)
                    .frame(maxWidth: 500)

                Divider()
                    .padding(.horizontal, 40)

                // MARK: - More Apps Section
                VStack(spacing: 16) {
                    Text("More Apps")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(alignment: .top, spacing: 20) {
                        // OptClicker
                        OtherAppCard(
                            imageName: "OptClickerIcon_Default",
                            appName: "OptClicker",
                            description: "Let you right-click with the Option key.",
                            url: "https://github.com/gitmichaelqiu/OptClicker"
                        )
                        
                        // SpaceSwitcher
                        OtherAppCard(
                            imageName: "SpaceSwitcherIcon_Default",
                            appName: "SpaceSwitcher",
                            description: "Control which app and dock to show in each space.",
                            url: "https://github.com/gitmichaelqiu/SpaceSwitcher"
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 10) // Extra padding for shadow/glow space
                }

                Divider()
                    .padding(.horizontal, 40)

                // MARK: - Footer
                VStack(spacing: 10) {
                    Link(NSLocalizedString("Settings.About.Repo", comment: "GitHub Repo"),
                         destination: URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer")!)
                    .font(.body)
                    .foregroundColor(.accentColor)

                    Text("© \(currentYear) Michael Yicheng Qiu")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct OtherAppCard: View {
    let imageName: String
    let appName: String
    let description: String
    let url: String
    
    @State private var isHovering = false
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 10) {
                // Icon
                if let nsImage = NSImage(named: imageName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 55, height: 55)
                        .shadow(radius: 2)
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                        .foregroundColor(.secondary)
                }
                
                // Text Content
                VStack(spacing: 4) {
                    Text(appName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(height: 40, alignment: .top)
                }
            }
            .padding(12)
            .frame(width: 160)
            .background(
                ZStack {
                    // 1. Base Card Background
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                    
                    // 2. Idle Border: Subtle gray stroke to define shape when not hovering
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    
                    // 3. Hover Ring: Accent color overlay that fades in
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(isHovering ? 1.0 : 0.0), lineWidth: 2)
                }
                // Shadow Logic:
                // 1. Base shadow (Slightly stronger now for better separation)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                // 2. Glow shadow (Fades in on hover)
                .shadow(color: .accentColor.opacity(isHovering ? 0.5 : 0.0), radius: 10, x: 0, y: 0)
            )
            .scaleEffect(isHovering ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
