import SwiftUI

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
    var shortcutNumber: Int? = nil
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
        HStack(spacing: LauncherLayout.rowSpacing) {
            LauncherIconSlot(systemName: command.iconName, tint: colors.textPrimary)
            
            Text(command.title)
                .font(LauncherTypography.rowTitle)
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            
            Spacer()
            
            if let statusText = toggleStatus {
                LauncherStatusLabel(
                    text: statusText == "Enabled" ? String(localized: "Enabled") : String(localized: "Disabled"),
                    color: statusText == "Enabled" ? colors.greenText : colors.textSecondary,
                    background: statusText == "Enabled" ? colors.greenText.opacity(0.12) : colors.badgeBg
                )
                .padding(
                    .trailing,
                    shortcutNumber == nil
                        ? 0
                        : LauncherLayout.commandNumberIndicatorWidth
                            + LauncherLayout.commandNumberIndicatorTrailingGap
                )
            } else if command.hasSubpage || command.type == .reloadLabels {
                if shortcutNumber == nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                        .padding(.trailing, 4)
                }
            }
        }
        .padding(.horizontal, LauncherLayout.rowHorizontalPadding)
        .padding(.vertical, LauncherLayout.rowVerticalPadding)
        .launcherRowSurface(isSelected: isSelected, isHovered: isHovered)
        .launcherCommandNumberOverlay(shortcutNumber)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
}

struct SpaceRowView: View {
    let space: SpaceGroup
    let isSelected: Bool
    let isCurrent: Bool
    var showDisplayName: Bool = true
    var shortcutNumber: Int? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: LauncherLayout.rowSpacing) {
            if isCurrent {
                CurrentSpaceIndicator()
            } else if space.isFullscreen, let appPath = space.appPath {
                let appIcon = NSWorkspace.shared.icon(forFile: appPath)
                LauncherIconSlot(image: appIcon)
            } else {
                LauncherIconSlot(systemName: "desktopcomputer", tint: colors.textPrimary)
            }
            
            Text(space.name)
                .font(LauncherTypography.rowTitle)
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)

            if space.isFullscreen {
                LauncherTrailingLabel(
                    showDisplayName
                        ? String(format: String(localized: "%@ · Fullscreen"), space.displayName)
                        : String(localized: "Fullscreen"),
                    color: isSelected ? colors.textSecondary : colors.textTertiary
                )
            } else {
                LauncherTrailingLabel(
                    showDisplayName
                        ? String(format: String(localized: "%@ · Space %lld"), space.displayName, space.num)
                        : String(format: String(localized: "Space %lld"), space.num),
                    color: isSelected ? colors.textSecondary : colors.textTertiary
                )
            }

            Spacer()

            if shortcutNumber == nil {
                KeycapView(text: String(localized: "Switch ↵"), isSelected: isSelected)
            }
        }
        .padding(.horizontal, LauncherLayout.rowHorizontalPadding)
        .padding(.vertical, LauncherLayout.rowVerticalPadding)
        .launcherRowSurface(isSelected: isSelected, isHovered: isHovered)
        .launcherCommandNumberOverlay(shortcutNumber)
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
            .frame(width: LauncherLayout.rowIconSlot, height: LauncherLayout.rowIconSlot)
            .accessibilityLabel(Text("Current space"))
    }
}

struct WindowStateBadge: View {
    let label: String
    let color: Color

    var body: some View {
        LauncherStatusLabel(text: label, color: color)
    }
}

struct WindowRowView: View {
    let window: WindowEntry
    let isSelected: Bool
    var shortcutNumber: Int? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: LauncherLayout.rowSpacing) {
            let appIcon = NSWorkspace.shared.icon(forFile: window.appPath)
            LauncherIconSlot(image: appIcon)

            Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                .font(LauncherTypography.rowTitle)
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            LauncherTrailingLabel(
                window.ownerName,
                color: isSelected ? colors.textSecondary : colors.textTertiary
            )

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

            }
            .padding(
                .trailing,
                shortcutNumber == nil
                    ? 0
                    : LauncherLayout.commandNumberIndicatorWidth
                        + LauncherLayout.commandNumberIndicatorTrailingGap
            )
        }
        .padding(.horizontal, LauncherLayout.rowHorizontalPadding)
        .padding(.vertical, LauncherLayout.rowVerticalPadding)
        .launcherRowSurface(isSelected: isSelected, isHovered: isHovered)
        .launcherCommandNumberOverlay(shortcutNumber)
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
                .font(LauncherTypography.rowTitle)
                .foregroundColor(isSelected ? .white : colors.greenText)
            
            Spacer()
            
            KeycapView(text: String(localized: "Run ↵"), isSelected: isSelected, isGreenRow: true)
        }
        .padding(.horizontal, LauncherLayout.rowHorizontalPadding)
        .padding(.vertical, LauncherLayout.rowVerticalPadding + 1)
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
    var shortcutNumber: Int? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: LauncherLayout.rowSpacing) {
            let appIcon = NSWorkspace.shared.icon(forFile: window.appPath)
            LauncherIconSlot(image: appIcon)

            Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                .font(LauncherTypography.rowTitle)
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            LauncherTrailingLabel(
                window.ownerName,
                color: isSelected ? colors.textSecondary : colors.textTertiary
            )

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

                if isStaged {
                    LauncherStatusLabel(
                        text: stagedActionText,
                        color: colors.greenText,
                        background: colors.greenText.opacity(0.12)
                    )
                }
            }
            .padding(
                .trailing,
                shortcutNumber == nil
                    ? 0
                    : LauncherLayout.commandNumberIndicatorWidth
                        + LauncherLayout.commandNumberIndicatorTrailingGap
            )
        }
        .padding(.horizontal, LauncherLayout.rowHorizontalPadding)
        .padding(.vertical, LauncherLayout.rowVerticalPadding)
        .launcherRowSurface(isSelected: isSelected, isHovered: isHovered)
        .launcherCommandNumberOverlay(shortcutNumber)
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
                .font(LauncherTypography.sectionHeader)
                .foregroundColor(colors.textSecondary)
            
            LauncherTrailingLabel(subtitle, color: colors.textSecondary)
            
            Spacer()
        }
        .padding(.horizontal, LauncherLayout.listHorizontalPadding)
        .padding(.top, isFirst ? 0 : LauncherLayout.sectionHeaderSpacing)
        .padding(.bottom, LauncherLayout.sectionHeaderBottomPadding)
    }
}
