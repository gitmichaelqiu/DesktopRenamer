import SwiftUI

struct ThemeColors {
    let isDark: Bool

    var backgroundOverlay: Color { Color.clear }
    var textPrimary: Color { .primary }
    var textSecondary: Color { .secondary }
    var textTertiary: Color { .secondary.opacity(0.65) }
    var textQuaternary: Color { .secondary.opacity(0.4) }
    var border: Color { Color(nsColor: .separatorColor) }
    var rowHover: Color { Color.primary.opacity(0.08) }
    var badgeBg: Color { Color.primary.opacity(0.06) }
    var badgeBorder: Color { Color.primary.opacity(0.08) }
    var separator: Color { Color(nsColor: .separatorColor) }
    var bottomBarBg: Color { Color.primary.opacity(0.01) }
    var greenText: Color { Color.green }
}
