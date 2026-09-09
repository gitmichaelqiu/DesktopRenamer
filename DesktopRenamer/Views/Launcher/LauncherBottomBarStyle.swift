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
        content
            .font(.subheadline)
            .fontWeight(isSelected || isActive ? .semibold : .medium)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                ZStack {
                    if isGreen {
                        if isSelected {
                            greenBgColor.opacity(isHovered ? 0.9 : 1.0)
                        } else if isActive {
                            greenBgColor.opacity(isHovered ? 0.25 : 0.15)
                        } else {
                            Color.primary.opacity(isHovered ? 0.12 : 0.06)
                        }
                    } else {
                        if isSelected {
                            isActive ? Color.primary.opacity(0.24) : Color.primary.opacity(0.16)
                        } else if isActive {
                            Color.primary.opacity(isHovered ? 0.22 : 0.14)
                        } else {
                            Color.primary.opacity(isHovered ? 0.12 : 0.06)
                        }
                    }
                }
            )
            .foregroundColor(
                isGreen ? (isSelected ? .white : (isActive ? greenBgColor : (isHovered ? greenBgColor : .secondary)))
                        : (isActive ? .primary : (isSelected || isHovered ? .primary : .secondary))
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isGreen ? (isSelected ? Color.primary.opacity(0.15) : (isActive ? greenBgColor.opacity(isHovered ? 0.4 : 0.2) : Color.primary.opacity(isHovered ? 0.25 : 0.08)))
                                : (isSelected ? (isActive ? Color.primary.opacity(0.48) : Color.primary.opacity(0.40)) : (isActive ? Color.primary.opacity(isHovered ? 0.35 : 0.22) : Color.primary.opacity(isHovered ? 0.25 : 0.08))),
                        lineWidth: (isSelected && !isGreen) ? 1.5 : 1
                    )
            )
            .shadow(color: isSelected ? (isGreen ? greenBgColor.opacity(0.25) : Color.primary.opacity(0.1)) : Color.clear, radius: 3, x: 0, y: 1)
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
