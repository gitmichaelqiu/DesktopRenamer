import SwiftUI

private enum LauncherSubmenu {
    case actions(WindowEntry)
    case spaces
}

struct LauncherSubmenuOverlay: View {
    @ObservedObject var viewModel: LauncherViewModel

    @State private var displayedSubmenu: LauncherSubmenu = .spaces
    @State private var isPresented = false

    private var requestedSubmenu: LauncherSubmenu? {
        if let targetWindow = viewModel.commandKTargetWindow {
            return .actions(targetWindow)
        }
        return viewModel.isSpaceMenuOpen ? .spaces : nil
    }

    private var requestedSubmenuKey: String {
        if let targetWindow = viewModel.commandKTargetWindow {
            return "actions-\(targetWindow.id)"
        }
        return viewModel.isSpaceMenuOpen ? "spaces" : "none"
    }

    var body: some View {
        ZStack {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .allowsHitTesting(isPresented)
                .onTapGesture {
                    if viewModel.commandKTargetWindow != nil {
                        viewModel.commandKTargetWindow = nil
                    } else {
                        viewModel.handleEscapeKey()
                    }
                }

            submenuView(for: displayedSubmenu)
                .offset(x: isPresented ? 0 : 6, y: isPresented ? 0 : 6)
                .opacity(isPresented ? 1 : 0)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(isPresented)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            synchronizeSubmenu()
        }
        .onChange(of: requestedSubmenuKey) { _ in
            synchronizeSubmenu()
        }
    }

    @ViewBuilder
    private func submenuView(for submenu: LauncherSubmenu) -> some View {
        switch submenu {
        case .actions(let window):
            LauncherActionMenuView(viewModel: viewModel, window: window)
        case .spaces:
            LauncherSpaceMenuView(viewModel: viewModel)
        }
    }

    private func synchronizeSubmenu() {
        guard let requestedSubmenu else {
            guard isPresented else { return }
            withAnimation(LauncherAnimation.submenuExit) {
                isPresented = false
            }
            return
        }

        displayedSubmenu = requestedSubmenu
        guard !isPresented else { return }
        withAnimation(LauncherAnimation.submenu) {
            isPresented = true
        }
    }
}

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
        }
        .padding(6)
        .frame(width: 380)
        .launcherFrosted(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct LauncherSpaceMenuView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @Environment(\.colorScheme) var colorScheme

    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    private var spaces: [SpaceGroup] { viewModel.spaceMenuSpaces }

    private var title: String {
        if let stagingWindow = viewModel.stagingWindow {
            return String(format: String(localized: "Move %@ to"), stagingWindow.ownerName)
        }

        return viewModel.activeCommand?.title ?? String(localized: "Select Space")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.callout)
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()
                .opacity(0.5)

            if spaces.isEmpty {
                Text(String(localized: "No spaces available"))
                    .font(.body)
                    .foregroundColor(colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                                LauncherSpaceMenuRow(
                                    space: space,
                                    isSelected: viewModel.spaceMenuSelectedIndex == index,
                                    isCurrent: SpaceHelper.getCurrentSpaceID(for: space.displayID) == space.id,
                                    shortcutNumber: index + 1,
                                    showShortcut: viewModel.showCommandNumbers && index < 9,
                                    colors: colors
                                ) {
                                    viewModel.isKeyboardSelection = true
                                    viewModel.spaceMenuSelectedIndex = index
                                    viewModel.executeSpaceMenuSelection()
                                }
                                .id(space.id)
                            }
                        }
                    }
                    .frame(height: min(max(CGFloat(spaces.count) * 42, 42), 300))
                    .scrollIndicators(.hidden)
                    .onAppear {
                        guard spaces.indices.contains(viewModel.spaceMenuSelectedIndex) else { return }
                        proxy.scrollTo(spaces[viewModel.spaceMenuSelectedIndex].id, anchor: .center)
                    }
                    .onChange(of: viewModel.spaceMenuSelectedIndex) { index in
                        guard spaces.indices.contains(index) else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo(spaces[index].id, anchor: .center)
                        }
                    }
                    .onChange(of: spaces.count) { count in
                        guard count > 0, viewModel.spaceMenuSelectedIndex >= count else { return }
                        viewModel.spaceMenuSelectedIndex = count - 1
                    }
                }
            }
        }
        .padding(6)
        .frame(width: 380)
        .launcherFrosted(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LauncherSpaceMenuRow: View {
    let space: SpaceGroup
    let isSelected: Bool
    let isCurrent: Bool
    let shortcutNumber: Int
    let showShortcut: Bool
    let colors: ThemeColors
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isCurrent {
                    Circle()
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: 18, height: 18)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                        .frame(width: 24, height: 24)
                }

                Text(space.name)
                    .font(.body)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(String(format: String(localized: "%@ · Space %lld"), space.displayName, space.num))
                    .font(.callout)
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)

                if showShortcut {
                    KeycapView(text: "⌘\(shortcutNumber)", isSelected: isSelected)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? colors.rowSelection : (isHovered ? colors.rowHover : .clear))
            }
            .contentShape(Rectangle())
            .animation(LauncherAnimation.fade, value: isSelected)
            .animation(LauncherAnimation.fade, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
                    .animation(LauncherAnimation.fade, value: showCommandNumbers)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? colors.rowSelection : (isHovered ? colors.rowHover : .clear))
            }
            .contentShape(Rectangle())
            .animation(LauncherAnimation.fade, value: isSelected)
            .animation(LauncherAnimation.fade, value: isHovered)
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
