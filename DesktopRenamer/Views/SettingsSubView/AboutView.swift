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
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 10) {
                // Try to load image from bundle resources, fallback to generic icon
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
