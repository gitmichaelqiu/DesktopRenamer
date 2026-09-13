import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        update(nsView)
    }

    private func update(_ view: NSVisualEffectView) {
        let isDark = colorScheme == .dark
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
    }
}

extension View {
    func launcherBackground(cornerRadius: CGFloat, borderColor: Color) -> some View {
        self
            .modifier(LauncherSurface(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}

private struct LauncherSurface: ViewModifier {
    let cornerRadius: CGFloat
    let borderColor: Color
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let colors = ThemeColors(isDark: colorScheme == .dark)
        content
            .background(colors.backgroundOverlay)
            .background {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor.opacity(0.9), lineWidth: 1)
            }
    }
}
