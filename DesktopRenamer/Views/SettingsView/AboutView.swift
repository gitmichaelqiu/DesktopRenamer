import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // App icon
                if let icon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .cornerRadius(10)
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                
                // App name
                Text(NSLocalizedString("About.AppName", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                
                // Version
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("v\(version)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                // Description
                Text(NSLocalizedString("About.Description", comment: ""))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                // GitHub link
                Button(action: openGitHub) {
                    Text(NSLocalizedString("About.GithubLink", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // Copyright
                let year = Calendar.current.component(.year, from: Date())
                let copyrightString = String(format: NSLocalizedString("About.Copyright", comment: ""), year)
                Text(copyrightString)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func openGitHub() {
        if let url = URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer") {
            NSWorkspace.shared.open(url)
        }
    }
}
