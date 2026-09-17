import SwiftUI

enum LauncherAnimation {
    static let capsule = Animation.spring(response: 0.28, dampingFraction: 0.85)
    static let submenu = Animation.easeOut(duration: 0.10)
    static let submenuExit = Animation.easeIn(duration: 0.10)
    static let submenuSwap = Animation.spring(response: 0.14, dampingFraction: 0.80, blendDuration: 0.01)
    static let fade = Animation.easeOut(duration: 0.14)
}

extension AnyTransition {
    static var launcherCapsule: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92, anchor: .center).combined(with: .opacity),
            removal: .scale(scale: 0.96, anchor: .center).combined(with: .opacity)
        )
    }

}

struct BottomBarCapsule: ViewModifier {
    let isSelected: Bool
    let isActive: Bool
    var isGreen: Bool = false
    let colorScheme: ColorScheme
    var isHoverEnabled: Bool = true
    var onHoverChange: ((Bool) -> Void)? = nil

    @State private var isHovered: Bool = false

    var greenBgColor: Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.48, blue: 0.26) : Color(red: 0.12, green: 0.44, blue: 0.22)
    }

    func body(content: Content) -> some View {
        let selectionFill = isGreen
            ? greenBgColor.opacity(isSelected ? 1 : (isActive ? 0.15 : 0))
            : Color.primary.opacity(isSelected ? (isActive ? 0.10 : 0.09) : (isActive ? 0.08 : 0))
        let neutralText = Color.primary.opacity(0.60)
        let showsHover = isHovered && isHoverEnabled

        content
            .font(LauncherTypography.bar)
            .padding(.horizontal, LauncherLayout.bottomBarControlHorizontalPadding)
            .frame(height: LauncherLayout.bottomBarControlHeight)
            .background(Capsule().fill(showsHover && !isSelected ? Color.primary.opacity(0.05) : selectionFill))
            .foregroundColor(
                isGreen ? (isSelected ? .white : (isActive ? greenBgColor : (showsHover ? greenBgColor : .secondary)))
                        : (isActive || isSelected || showsHover ? .primary : neutralText)
            )
            .clipShape(Capsule())
            .animation(LauncherAnimation.capsule, value: isSelected)
            .animation(LauncherAnimation.fade, value: isActive)
            .animation(LauncherAnimation.fade, value: showsHover)
            .onHover { hovering in
                isHovered = hovering
                onHoverChange?(hovering)
            }
    }
}

struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 210

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
