import SwiftUI

struct LauncherActionMenuView: View {
    @ObservedObject var viewModel: LauncherViewModel
    let window: WindowEntry
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                let appIcon = NSWorkspace.shared.icon(forFile: window.appPath)
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                        .font(.headline)
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1)

                    Text(window.ownerName)
                        .font(.callout)
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .opacity(0.5)

            let actionItems = viewModel.commandKActions.enumerated().map { index, action in
                ActionMenuItem(index: index, action: action)
            }
            LazyVStack(spacing: 2) {
                ForEach(actionItems) { item in
                    CommandKActionRowView(
                        action: item.action,
                        isSelected: viewModel.commandKSelectedIndex == item.index,
                        showCommandNumbers: viewModel.showCommandNumbers,
                        idx: item.index,
                        colors: colors,
                        viewModel: viewModel
                    )
                }
            }
            .padding(8)
        }
        .frame(width: 380)
        .launcherFrosted(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct ActionMenuItem: Identifiable {
    let index: Int
    let action: BatchStagedActionType

    var id: String {
        "\(index)-\(action.description)"
    }
}

struct CommandKActionRowView: View {
    let action: BatchStagedActionType
    let isSelected: Bool
    let showCommandNumbers: Bool
    let idx: Int
    let colors: ThemeColors
    @ObservedObject var viewModel: LauncherViewModel
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            viewModel.commandKSelectedIndex = idx
            viewModel.executeCommandKAction()
        }) {
            HStack(spacing: 10) {
                Image(systemName: getIconName(for: action))
                    .font(.body.weight(.medium))
                    .frame(width: 20)
                    .foregroundColor(isSelected ? colors.textPrimary : colors.textSecondary)

                Text(getActionLabel(for: action))
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(colors.textPrimary)

                Spacer(minLength: 0)

                KeycapView(text: "⌘\(idx + 1)", isSelected: isSelected)
                    .opacity(showCommandNumbers ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? colors.rowSelection : (isHovered ? colors.rowHover : .clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func getIconName(for action: BatchStagedActionType) -> String {
        switch action {
        case .close: return "xmark"
        case .minimize: return "minus"
        case .hide: return "eye.slash"
        case .enterFullScreen: return "arrow.up.left.and.arrow.down.right"
        case .exitFullScreen: return "arrow.down.right.and.arrow.up.left"
        case .quit: return "power"
        case .restore: return "arrow.uturn.backward"
        case .restoreTo: return "arrow.forward.square"
        case .move: return "arrow.right.square"
        }
    }
    
    private func getActionLabel(for action: BatchStagedActionType) -> String {
        switch action {
        case .close: return NSLocalizedString("Close", comment: "")
        case .minimize: return NSLocalizedString("Minimize", comment: "")
        case .hide: return NSLocalizedString("Hide", comment: "")
        case .enterFullScreen: return NSLocalizedString("Enter Full Screen", comment: "")
        case .exitFullScreen: return NSLocalizedString("Exit Full Screen", comment: "")
        case .quit: return NSLocalizedString("Quit", comment: "")
        case .restore: return NSLocalizedString("Restore", comment: "")
        case .restoreTo(let space): return space.name.isEmpty ? NSLocalizedString("Restore to...", comment: "") : String(format: NSLocalizedString("Restore to %@", comment: ""), space.name)
        case .move(let space): return space.name.isEmpty ? NSLocalizedString("Move to...", comment: "") : String(format: NSLocalizedString("Move to %@", comment: ""), space.name)
        }
    }
}
