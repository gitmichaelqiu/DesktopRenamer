import SwiftUI

struct ThemeColors {
    let isDark: Bool

    private var ink: Color { isDark ? .white : .black }

    var backgroundOverlay: Color { isDark ? Color.black.opacity(0.40) : Color.white.opacity(0.55) }
    var textPrimary: Color { ink }
    var textSecondary: Color { ink.opacity(0.60) }
    var textTertiary: Color { ink.opacity(isDark ? 0.40 : 0.42) }
    var textQuaternary: Color { ink.opacity(isDark ? 0.25 : 0.28) }
    var border: Color { ink.opacity(isDark ? 0.20 : 0.18) }
    var rowHover: Color { ink.opacity(isDark ? 0.05 : 0.045) }
    var rowSelection: Color { ink.opacity(isDark ? 0.10 : 0.09) }
    var badgeBg: Color { ink.opacity(isDark ? 0.10 : 0.08) }
    var badgeBorder: Color { ink.opacity(isDark ? 0.20 : 0.18) }
    /// A small raised surface must use an explicit ink color so it stays lighter than a dark selected row.
    var controlSurface: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08) }
    var separator: Color { Color.primary.opacity(isDark ? 0.10 : 0.12) }
    var bottomBarBg: Color { Color.primary.opacity(isDark ? 0.04 : 0.035) }
    var greenText: Color { Color.green }
}
