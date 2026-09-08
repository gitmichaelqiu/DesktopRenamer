import SwiftUI
import AVKit

struct LaunchersPage: View {
    var openURL: OpenURLAction
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var launcherViewModel: LauncherViewModel

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                Text("Launchers")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                
                Text("Choose Raycast or the built-in launcher to manage your Spaces and windows.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
            }

            HStack(alignment: .top, spacing: 20) {
                LauncherShowcase(
                    title: "Raycast",
                    imageName: "RaycastExtension",
                    imageFallbackSymbol: "puzzlepiece.extension.fill"
                ) {
                    Button(action: {
                        if let url = URL(string: "https://www.raycast.com/michael_qiu/desktoprenamer") {
                            openURL(url)
                        }
                    }) {
                        Label("Install Extension", systemImage: "arrow.down.circle.fill")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                LauncherShowcase(
                    title: "DesktopRenamer",
                    imageName: "DesktopRenamerLauncher",
                    imageFallbackSymbol: "rectangle.and.text.magnifyingglass"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Open launcher")
                            Spacer()
                            Text(hotkeyManager.description(for: .launcher))
                                .foregroundColor(.secondary)
                            Button("◉") {
                                hotkeyManager.startListening(for: .launcher)
                            }
                            .disabled(hotkeyManager.isListening)
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .launcher)
                            }
                            .disabled(hotkeyManager.isDefault(for: .launcher))
                        }

                        Toggle("Automatically rank commands", isOn: $launcherViewModel.automaticallyRankCommands)
                            .toggleStyle(.switch)
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.top, 20)
    }
}

private struct LauncherShowcase<Controls: View>: View {
    let title: String
    let imageFallbackSymbol: String
    let image: NSImage?
    @ViewBuilder let controls: () -> Controls

    init(
        title: String,
        imageName: String,
        imageFallbackSymbol: String,
        @ViewBuilder controls: @escaping () -> Controls
    ) {
        self.title = title
        self.imageFallbackSymbol = imageFallbackSymbol
        self.image = Bundle.main.url(forResource: imageName, withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
        self.controls = controls
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            } else {
                Image(systemName: imageFallbackSymbol)
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            controls()
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
