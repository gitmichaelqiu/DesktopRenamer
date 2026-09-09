import SwiftUI
struct CommandKOverlayView: View {
    @ObservedObject var viewModel: LauncherViewModel
    let window: WindowEntry
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        ZStack {
            // Subtle separation overlay (dimming in dark theme, neutral in light theme)
            (colorScheme == .dark ? Color.black.opacity(0.25) : Color.black.opacity(0.03))
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    viewModel.commandKTargetWindow = nil
                }
            
            // Centered panel card
            VStack(spacing: 0) {
                // Header details
                HStack(spacing: 12) {
                    let appIcon = NSWorkspace.shared.icon(forFile: window.appPath)
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .padding(4)
                        .background(colors.badgeBg)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(colors.badgeBorder, lineWidth: 1)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundColor(colors.textPrimary)
                            .lineLimit(1)
                        
                        Text(window.ownerName)
                            .font(.subheadline)
                            .foregroundColor(colors.textSecondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // State Badges
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                
                Divider()
                
                // Actions List
                let actions = viewModel.commandKActions
                VStack(spacing: 2) {
                    ForEach(0..<actions.count, id: \.self) { idx in
                        let action = actions[idx]
                        let isSelected = viewModel.commandKSelectedIndex == idx
                        
                        CommandKActionRowView(
                            action: action,
                            isSelected: isSelected,
                            showCommandNumbers: viewModel.showCommandNumbers,
                            idx: idx,
                            colors: colors,
                            viewModel: viewModel
                        )
                    }
                }
                .padding(8)
            }
            .frame(width: 380)
            .launcherBackground(cornerRadius: 12, borderColor: colors.border)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.2), radius: 15, x: 0, y: 8)
        }
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
        HStack(spacing: 10) {
            Image(systemName: getIconName(for: action))
                .font(.body.weight(.medium))
                .frame(width: 16)
                .foregroundColor(isSelected ? colors.textPrimary : colors.textSecondary)
            
            Text(getActionLabel(for: action))
                .font(.body)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(colors.textPrimary)
            
            Spacer()
            
            KeycapView(text: "⌘\(idx + 1)", isSelected: isSelected)
                .opacity(showCommandNumbers ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            viewModel.commandKSelectedIndex = idx
            viewModel.executeCommandKAction()
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


