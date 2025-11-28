import SwiftUI

struct SettingsRow<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content
    let helperText: LocalizedStringKey?
    
    @State private var showingHelperPopover = false

    init(_ title: LocalizedStringKey, helperText: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.helperText = helperText
        self.content = content()
    }

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text(title)
                    .frame(alignment: .leading)
                
                if let helperText = helperText {
                    Button {
                        showingHelperPopover.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingHelperPopover, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(helperText)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(15)
                        .frame(minWidth: 200, maxWidth: 300)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content
                .frame(alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }
}

struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.regularMaterial)
                    )
            )
        }
    }

    private var backgroundColor: Color {
        let nsColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.20, alpha: 1.0)
            } else {
                return NSColor(calibratedWhite: 1.00, alpha: 1.0)
            }
        }
        return Color(nsColor: nsColor)
    }
}
