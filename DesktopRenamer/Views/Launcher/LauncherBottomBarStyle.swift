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
            .font(.callout.weight(.medium))
            .padding(.horizontal, 8)
            .frame(height: 28)
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
                            isActive ? Color.primary.opacity(0.18) : Color.primary.opacity(0.10)
                        } else if isActive {
                            Color.primary.opacity(isHovered ? 0.12 : 0.08)
                        } else if isHovered {
                            Color.primary.opacity(0.05)
                        } else {
                            Color.clear
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
                        isGreen ? (isSelected ? Color.primary.opacity(0.15) : (isActive ? greenBgColor.opacity(isHovered ? 0.4 : 0.2) : Color.clear))
                                : (isSelected ? Color.primary.opacity(0.22) : (isActive ? Color.primary.opacity(isHovered ? 0.16 : 0.10) : Color.clear)),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.clear, radius: 0)
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
