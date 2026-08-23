import SwiftUI
struct KeycapView: View {
    let text: LocalizedStringKey
    let isSelected: Bool
    var isGreenRow: Bool = false
    var verticalPadding: CGFloat = 3
    var horizontalPadding: CGFloat = 6
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        let isSelectedWhiteStyle = isSelected && (colorScheme == .dark || isGreenRow)
        
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(isSelected ? (isSelectedWhiteStyle ? .white : colors.textPrimary) : colors.textSecondary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                isSelected
                    ? (isSelectedWhiteStyle ? Color.white.opacity(0.20) : Color.primary.opacity(0.12))
                    : colors.badgeBg
            )
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        isSelected
                            ? (isSelectedWhiteStyle ? Color.white.opacity(0.30) : Color.primary.opacity(0.18))
                            : colors.badgeBorder,
                        lineWidth: 1
                    )
            )
    }
}

struct EmptyResultsView: View {
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(colors.textQuaternary)
            Text(verbatim: String(localized: "No results"))
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(colors.textTertiary)
            Text(verbatim: String(localized: "No commands matched your search query."))
                .font(.subheadline)
                .foregroundColor(colors.textQuaternary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CommandRowView: View {
    let command: LauncherCommand
    let isSelected: Bool
    var shortcutText: String? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    // Observers for settings changes to trigger auto-redraw of status labels
    @AppStorage("kShowActiveLabels") private var showActiveLabels = true
    @AppStorage("kShowPreviewLabels") private var showPreviewLabels = true
    @AppStorage("kShowOnDesktop") private var showOnDesktop = false
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    private var toggleStatus: String? {
        switch command.type {
        case .toggleActiveLabel:
            return showActiveLabels ? "Enabled" : "Disabled"
        case .togglePreviewLabel:
            return showPreviewLabels ? "Enabled" : "Disabled"
        case .toggleActiveLabelVisibility:
            return showOnDesktop ? "Enabled" : "Disabled"
        default:
            return nil
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.iconName)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(colors.textPrimary)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                
                Text(command.subtitle)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let shortcut = shortcutText {
                KeycapView(text: LocalStringKey_compat(shortcut), isSelected: isSelected)
            } else if let statusText = toggleStatus {
                Text(LocalizedStringKey(statusText))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(statusText == "Enabled" ? colors.greenText : colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusText == "Enabled" ? colors.greenText.opacity(0.12) : colors.badgeBg)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(statusText == "Enabled" ? colors.greenText.opacity(0.35) : colors.badgeBorder, lineWidth: 1)
                    )
            } else if command.hasSubpage {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .padding(.trailing, 4)
            } else {
                KeycapView(text: "Action", isSelected: isSelected)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    // Helper to safely wrap dynamic String to LocalizedStringKey
    private func LocalStringKey_compat(_ str: String) -> LocalizedStringKey {
        return LocalizedStringKey(str)
    }
}

struct SpaceRowView: View {
    let space: SpaceGroup
    let isSelected: Bool
    let isCurrent: Bool
    var shortcutText: String? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if space.isFullscreen, let appPath = space.appPath {
                let appIcon = ApplicationIconCache.icon(forFilePath: appPath)
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                    .frame(width: 32, height: 32)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(space.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                
                if space.isFullscreen {
                    Text(verbatim: String(format: String(localized: "%@ · Fullscreen"), space.displayName))
                        .font(.subheadline)
                        .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(verbatim: String(format: String(localized: "%@ · Space %lld"), space.displayName, space.num))
                        .font(.subheadline)
                        .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()

            if isCurrent {
                WindowStateBadge(label: String(localized: "Current"), color: .blue)
            }

            if let shortcut = shortcutText {
                KeycapView(text: LocalizedStringKey(shortcut), isSelected: isSelected)
            } else {
                KeycapView(text: "Switch ↵", isSelected: isSelected)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct WindowStateBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }
}

struct WindowRowView: View {
    let window: WindowEntry
    let isSelected: Bool
    var shortcutText: String? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            let appIcon = ApplicationIconCache.icon(forFilePath: window.appPath)
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)

                Text(window.ownerName)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                if window.isHidden {
                    WindowStateBadge(label: String(localized: "Hidden"), color: .purple)
                } else if window.isMinimized {
                    WindowStateBadge(label: String(localized: "Minimized"), color: .orange)
                }
                if window.space.isFullscreen {
                    WindowStateBadge(label: String(localized: "Full Screen"), color: .blue)
                }

                if let shortcut = shortcutText {
                    KeycapView(text: LocalizedStringKey(shortcut), isSelected: isSelected)
                } else {
                    KeycapView(text: "Focus ↵", isSelected: isSelected)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ConfirmBatchRowView: View {
    let count: Int
    let isSelected: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundColor(isSelected ? colors.greenText : .white)
                .frame(width: 28, height: 28)
                .background(isSelected ? .white : colors.greenText.opacity(0.8))
                .cornerRadius(6)
            
            Text(verbatim: String(format: String(localized: "Confirm & Execute Batch Move (%lld windows)"), count))
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? .white : colors.greenText)
            
            Spacer()
            
            KeycapView(text: "Run ↵", isSelected: isSelected, isGreenRow: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(isSelected ? colors.greenText : (isHovered ? colors.greenText.opacity(0.5) : colors.greenText.opacity(0.06)))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colors.greenText.opacity(isSelected ? 0.3 : 0.1), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct WindowBatchRowView: View {
    let window: WindowEntry
    let isSelected: Bool
    let isStaged: Bool
    let stagedActionText: String
    var shortcutText: String? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            let appIcon = ApplicationIconCache.icon(forFilePath: window.appPath)
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)

                Text(window.ownerName)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                if !isStaged {
                    if window.isHidden {
                        WindowStateBadge(label: String(localized: "Hidden"), color: .purple)
                    } else if window.isMinimized {
                        WindowStateBadge(label: String(localized: "Minimized"), color: .orange)
                    }
                    if window.space.isFullscreen {
                        WindowStateBadge(label: String(localized: "Full Screen"), color: .blue)
                    }
                }

                if let shortcut = shortcutText {
                    KeycapView(text: LocalizedStringKey(shortcut), isSelected: isSelected)
                } else if isStaged {
                    Text(stagedActionText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(colors.greenText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(colors.greenText.opacity(0.12))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(colors.greenText.opacity(0.35), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ListSectionHeader: View {
    let title: String
    let subtitle: String
    var isFirst: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(colors.textSecondary)
            
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(colors.textSecondary)
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, isFirst ? 0 : 10)
        .padding(.bottom, 4)
    }
}

