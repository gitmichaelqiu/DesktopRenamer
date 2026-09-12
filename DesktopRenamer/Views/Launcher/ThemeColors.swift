import SwiftUI

struct ThemeColors {
    let isDark: Bool

    var backgroundOverlay: Color {
        isDark ? Color.black.opacity(0.30) : Color.white.opacity(0.32)
    }
    var textPrimary: Color { .primary }
    var textSecondary: Color { Color.primary.opacity(isDark ? 0.68 : 0.62) }
    var textTertiary: Color { Color.primary.opacity(isDark ? 0.46 : 0.48) }
    var textQuaternary: Color { Color.primary.opacity(isDark ? 0.30 : 0.34) }
    var border: Color { Color.primary.opacity(isDark ? 0.18 : 0.14) }
    var rowHover: Color { Color.primary.opacity(isDark ? 0.07 : 0.055) }
    var rowSelection: Color { Color.primary.opacity(isDark ? 0.13 : 0.10) }
    var badgeBg: Color { Color.primary.opacity(isDark ? 0.09 : 0.07) }
    var badgeBorder: Color { Color.primary.opacity(isDark ? 0.18 : 0.14) }
    var separator: Color { Color.primary.opacity(isDark ? 0.12 : 0.10) }
    var bottomBarBg: Color { Color.primary.opacity(isDark ? 0.035 : 0.025) }
    var greenText: Color { Color.green }
}
