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
            VStack(alignment: .leading, spacing: 32) {
                // Header Section
                HStack(spacing: 20) {
                    if let nsImage = NSApplication.shared.applicationIconImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appName)
                            .font(.system(size: 32, weight: .bold))
                        
                        Text("v\(appVersion)")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        Text("© \(currentYear) Michael Yicheng Qiu")
                            .font(.footnote)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                .padding(.top, 10)

                // Links Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Links")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        AboutLinkRow(title: "DesktopRenamer's website", url: "https://gitmichaelqiu.github.io/DesktopRenamer")
                        AboutLinkRow(title: "DesktopRenamer's GitHub", url: "https://github.com/gitmichaelqiu/DesktopRenamer")
                        AboutLinkRow(title: "My website", url: "https://gitmichaelqiu.github.io")
                        AboutLinkRow(title: "My GitHub", url: "https://github.com/gitmichaelqiu")
                    }
                }

                // More Apps Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("More Apps")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 12) {
                        OtherAppRow(
                            imageName: "OptClickerIcon_Default",
                            appName: "OptClicker",
                            description: "Let you right-click with the Option key.",
                            url: "https://github.com/gitmichaelqiu/OptClicker"
                        )
                        
                        OtherAppRow(
                            imageName: "SpaceSwitcherIcon_Default",
                            appName: "SpaceSwitcher",
                            description: "Control which app and dock to show in each space.",
                            url: "https://github.com/gitmichaelqiu/SpaceSwitcher"
                        )
                    }
                }

                // Acknowledgements Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Acknowledgements")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Button(action: openAcknowledgements) {
                        HStack {
                            Image(systemName: "doc.plaintext.fill")
                            Text("View Acknowledgements (PDF)")
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func openAcknowledgements() {
        if let pdfPath = Bundle.main.path(forResource: "Acknowledgements", ofType: "pdf", inDirectory: "Acknowledgements") {
            let url = URL(fileURLWithPath: pdfPath)
            NSWorkspace.shared.open(url)
        } else {
            // Fallback: search by direct path if bundle fails (useful during dev)
            let directPath = "/Users/michaelqiu/Projects/03_App_macOS/DesktopRenamer/DesktopRenamer/Resources/Acknowledgements/Acknowledgements.pdf"
            let url = URL(fileURLWithPath: directPath)
            if FileManager.default.fileExists(atPath: directPath) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

struct AboutLinkRow: View {
    let title: String
    let url: String
    
    @State private var isHovering = false
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 4) {
                Text(title)
                    .foregroundColor(isHovering ? .accentColor : .secondary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
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

struct OtherAppRow: View {
    let imageName: String
    let appName: String
    let description: String
    let url: String
    
    @State private var isHovering = false
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    if let nsImage = NSImage(named: imageName) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                            .foregroundColor(.secondary)
                    }
                }
                .shadow(color: .black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 6 : 2, x: 0, y: 2)
                .scaleEffect(isHovering ? 1.05 : 1.0)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if isHovering {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovering ? Color.accentColor.opacity(0.05) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovering ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
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
            VStack(spacing: 12) {
                // Icon
                if let nsImage = NSImage(named: imageName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .shadow(color: .black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 8 : 4, x: 0, y: 2)
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 55, height: 55)
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
            .padding(16)
            .frame(width: 170)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(NSColor.controlBackgroundColor))
                    
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isHovering ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 1)
                }
            )
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
