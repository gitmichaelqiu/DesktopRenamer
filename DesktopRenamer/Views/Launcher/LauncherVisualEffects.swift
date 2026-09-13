import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        update(nsView)
    }

    private func update(_ view: NSVisualEffectView) {
        // Let the panel's effective appearance drive the native material, as it does in Tinycast.
        view.appearance = nil
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
    }
}

extension View {
    func launcherBackground(cornerRadius: CGFloat) -> some View {
        modifier(LauncherSurface(cornerRadius: cornerRadius))
    }

    func launcherFrosted<ShapeType: Shape>(in shape: ShapeType) -> some View {
        modifier(LauncherFrostedSurface(shape: shape))
    }
}

private struct LauncherSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let colors = ThemeColors(isDark: colorScheme == .dark)
        content
            .background(colors.backgroundOverlay)
            .background {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct LauncherFrostedSurface<ShapeType: Shape>: ViewModifier {
    let shape: ShapeType
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let tint = colorScheme == .dark
            ? Color.white.opacity(0.05)
            : Color.white.opacity(0.25)

        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive().tint(tint), in: shape)
                .tint(.clear)
        } else {
            content
                .background {
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(shape)
                }
                .background(shape.fill(tint))
                .clipShape(shape)
        }
    }
}
