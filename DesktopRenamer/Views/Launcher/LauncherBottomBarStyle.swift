import SwiftUI

struct BottomBarCapsule: ViewModifier {
    let isSelected: Bool
    let isActive: Bool
    var isGreen: Bool = false
    let colorScheme: ColorScheme

    @State private var isHovered: Bool = false

    var greenBgColor: Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.48, blue: 0.26) : Color(red: 0.12, green: 0.44, blue: 0.22)
    }

    func body(content: Content) -> some View {
        let selectionFill = isGreen
            ? greenBgColor.opacity(isSelected ? 1 : (isActive ? 0.15 : 0))
            : Color.primary.opacity(isSelected ? (isActive ? 0.10 : 0.09) : (isActive ? 0.08 : 0))

        content
            .font(.callout.weight(.medium))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Capsule().fill(isHovered && !isSelected ? Color.primary.opacity(0.05) : selectionFill))
            .foregroundColor(
                isGreen ? (isSelected ? .white : (isActive ? greenBgColor : (isHovered ? greenBgColor : .secondary)))
                        : (isActive ? .primary : (isSelected || isHovered ? .primary : .secondary))
            )
            .clipShape(Capsule())
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 210

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
