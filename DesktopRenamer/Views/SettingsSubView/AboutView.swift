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
        VStack(spacing: 12) {
            if let nsImage = NSApplication.shared.applicationIconImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .padding(.bottom, 8)
            }

            Text(appName)
                .font(.largeTitle)
                .bold()

            Text("v\(appVersion)")
                .font(.title3)
                .foregroundColor(.secondary)

            Divider()
                .padding(.vertical, 8)

            Text(NSLocalizedString("Settings.About.Description", comment: "Description"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360, alignment: .center)
//                .fixedSize(horizontal: false, vertical: true)
                .font(.body)
            
            Spacer()
            
            Link(NSLocalizedString("Settings.About.Repo", comment: "GitHub Repo"), destination: URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer")!)
                .font(.body)
                .foregroundColor(.blue)

            Text("© \(currentYear) Michael Yicheng Qiu")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: CGFloat(defaultSettingsWindowHeight), alignment: .topLeading)
    }
}
