import SwiftUI

private struct LauncherRowSurface: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let colors = ThemeColors(isDark: colorScheme == .dark)
        content
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? colors.rowSelection : (isHovered ? colors.rowHover : .clear))
            }
    }
}

private extension View {
    func launcherRowSurface(isSelected: Bool, isHovered: Bool) -> some View {
        modifier(LauncherRowSurface(isSelected: isSelected, isHovered: isHovered))
    }
}

struct KeycapView: View {
    let text: String
    let isSelected: Bool
    var isGreenRow: Bool = false
    var verticalPadding: CGFloat = 1
    var horizontalPadding: CGFloat = 4
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    private var tokens: [String] {
        if text.contains(" ") {
            return text.split(separator: " ").map(String.init)
        }
        if text.count > 1 && text.contains(where: { "⌘⌥⇧⌃".contains($0) }) {
            return text.map(String.init)
        }
        return [text]
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tokens, id: \.self) { token in
                Text(verbatim: token)
                    .font(.caption)
                    .foregroundStyle(isSelected && isGreenRow ? .white : colors.textSecondary)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .frame(minWidth: 18, minHeight: 18)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected && isGreenRow ? Color.white.opacity(0.16) : Color.clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(colors.border, lineWidth: 1)
                    }
            }
        }
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
        HStack(spacing: 10) {
            Image(systemName: command.iconName)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(colors.textPrimary)
                .frame(width: 24, height: 24)
            
            Text(command.title)
                .font(.body)
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            
            Text(command.subtitle)
                .font(.callout)
                .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
            
            if let shortcut = shortcutText {
                KeycapView(text: shortcut, isSelected: isSelected)
            } else if let statusText = toggleStatus {
                Text(LocalizedStringKey(statusText))
                    .font(.subheadline)
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
                KeycapView(text: String(localized: "Action"), isSelected: isSelected)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .launcherRowSurface(isSelected: isSelected, isHovered: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
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
        HStack(spacing: 10) {
            if isCurrent {
                CurrentSpaceIndicator()
            } else if space.isFullscreen, let appPath = space.appPath {
                let appIcon = NSWorkspace.shared.icon(forFile: appPath)
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                    .frame(width: 24, height: 24)
            }
            
            Text(space.name)
                .font(.body)
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)

            if space.isFullscreen {
                Text(verbatim: String(format: String(localized: "%@ · Fullscreen"), space.displayName))
                    .font(.callout)
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            } else {
                Text(verbatim: String(format: String(localized: "%@ · Space %lld"), space.displayName, space.num))
                    .font(.callout)
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let shortcut = shortcutText {
                KeycapView(text: shortcut, isSelected: isSelected)
            } else {
                KeycapView(text: String(localized: "Switch ↵"), isSelected: isSelected)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .launcherRowSurface(isSelected: isSelected, isHovered: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct CurrentSpaceIndicator: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .stroke(Color.blue, lineWidth: 2)
            .frame(width: 18, height: 18)
            .frame(width: 24, height: 24)
            .accessibilityLabel(Text("Current space"))
    }
}

struct WindowStateBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.footnote)
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
        HStack(spacing: 8) {
            let appIcon = NSWorkspace.shared.icon(forFile: window.appPath)
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                .font(.body)
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Spacer()

            Text(window.ownerName)
                .font(.callout)
                .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                .lineLimit(1)

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
                    KeycapView(text: shortcut, isSelected: isSelected)
                } else {
                    KeycapView(text: String(localized: "Focus ↵"), isSelected: isSelected)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .launcherRowSurface(isSelected: isSelected, isHovered: isHovered)
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
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundColor(isSelected ? colors.greenText : .white)
                .frame(width: 28, height: 28)
                .background(isSelected ? .white : colors.greenText.opacity(0.8))
                .cornerRadius(6)
            
            Text(verbatim: String(format: String(localized: "Confirm & Execute Batch Move (%lld windows)"), count))
                .font(.body)
                .foregroundColor(isSelected ? .white : colors.greenText)
            
            Spacer()
            
            KeycapView(text: String(localized: "Run ↵"), isSelected: isSelected, isGreenRow: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
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
            let appIcon = NSWorkspace.shared.icon(forFile: window.appPath)
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                .font(.body)
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Spacer()

            Text(window.ownerName)
                .font(.callout)
                .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                .lineLimit(1)

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
                    KeycapView(text: shortcut, isSelected: isSelected)
                } else if isStaged {
                    Text(stagedActionText)
                        .font(.subheadline)
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
        .padding(.vertical, 6)
        .launcherRowSurface(isSelected: isSelected, isHovered: isHovered)
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
                .font(.subheadline.weight(.medium))
                .foregroundColor(colors.textSecondary)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(colors.textSecondary)
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, isFirst ? 0 : 10)
        .padding(.bottom, 4)
    }
}
