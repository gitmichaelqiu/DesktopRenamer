import SwiftUI

private enum LauncherSubmenu {
    case actions(window: WindowEntry, actions: [BatchStagedActionType])
    case spaces
}

struct LauncherSubmenuOverlay: View {
    @ObservedObject var viewModel: LauncherViewModel

    @State private var displayedSubmenu: LauncherSubmenu = .spaces
    @State private var isPresented = false

    private var requestedSubmenu: LauncherSubmenu? {
        if let targetWindow = viewModel.commandKTargetWindow {
            return .actions(
                window: targetWindow,
                actions: viewModel.getAvailableCommandKActions(for: targetWindow)
            )
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
        case .actions(let window, let actions):
            LauncherActionMenuView(viewModel: viewModel, window: window, actions: actions)
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
    let actions: [BatchStagedActionType]
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        LauncherSubmenuPanel {
            VStack(spacing: 0) {
                LauncherSubmenuHeader {
                    LauncherSubmenuWindowHeader(window: window)
                }

                LauncherSubmenuSeparator()

                let actionItems = actions.enumerated().map { index, action in
                    ActionMenuItem(index: index, action: action)
                }
                LazyVStack(spacing: LauncherLayout.submenuRowSpacing) {
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
        }
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
        viewModel.activeCommand?.title ?? String(localized: "Select Space")
    }

    var body: some View {
        LauncherSubmenuPanel {
            VStack(alignment: .leading, spacing: 0) {
                LauncherSubmenuHeader {
                    if let stagingWindow = viewModel.stagingWindow {
                        LauncherSubmenuWindowHeader(window: stagingWindow)
                    } else {
                        LauncherSubmenuTitleHeader(title: title, color: colors.textSecondary)
                    }
                }

                LauncherSubmenuSeparator()

                if spaces.isEmpty {
                    Text(String(localized: "No spaces available"))
                        .font(LauncherTypography.submenuRow)
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(LauncherLayout.submenuRowHorizontalPadding)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: LauncherLayout.submenuRowSpacing) {
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
                        .frame(height: spaceMenuHeight)
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
        }
    }

    private var spaceMenuHeight: CGFloat {
        let rowCount = CGFloat(spaces.count)
        let contentHeight = rowCount * LauncherLayout.submenuRowHeight
            + max(rowCount - 1, 0) * LauncherLayout.submenuRowSpacing
        return min(max(contentHeight, LauncherLayout.submenuRowHeight), 300)
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

    var body: some View {
        LauncherSubmenuRow(isSelected: isSelected, action: action) {
            HStack(spacing: LauncherLayout.submenuRowContentSpacing) {
                if isCurrent {
                    Circle()
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: 18, height: 18)
                        .frame(
                            width: LauncherLayout.submenuIconSlot,
                            height: LauncherLayout.submenuIconSlot
                        )
                } else {
                    LauncherIconSlot(
                        systemName: "desktopcomputer",
                        tint: colors.textSecondary,
                        slot: LauncherLayout.submenuIconSlot
                    )
                }

                Text(space.name)
                    .font(LauncherTypography.submenuRow)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: LauncherLayout.submenuRowContentSpacing)

                LauncherTrailingLabel(
                    String(format: String(localized: "%@ · Space %lld"), space.displayName, space.num),
                    color: colors.textSecondary
                )

                if showShortcut {
                    KeycapView(text: "⌘\(shortcutNumber)", isSelected: isSelected)
                }
            }
        }
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
    
    var body: some View {
        LauncherSubmenuRow(
            isSelected: isSelected,
            action: {
                viewModel.commandKSelectedIndex = idx
                viewModel.executeCommandKAction()
            }
        ) {
            HStack(spacing: LauncherLayout.submenuRowContentSpacing) {
                LauncherIconSlot(
                    systemName: getIconName(for: action),
                    tint: isSelected ? colors.textPrimary : colors.textSecondary,
                    slot: LauncherLayout.submenuIconSlot
                )

                Text(getActionLabel(for: action))
                    .font(LauncherTypography.submenuRow)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                KeycapView(text: "⌘\(idx + 1)", isSelected: isSelected)
                    .opacity(showCommandNumbers ? 1 : 0)
                    .animation(LauncherAnimation.fade, value: showCommandNumbers)
            }
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
