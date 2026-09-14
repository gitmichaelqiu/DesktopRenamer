import SwiftUI

private enum LauncherSubmenu {
    case actions(window: WindowEntry)
    case spaces
}

struct LauncherSubmenuOverlay: View {
    @ObservedObject var viewModel: LauncherViewModel

    @State private var displayedSubmenu: LauncherSubmenu = .spaces
    @State private var isPresented = false

    private var requestedSubmenu: LauncherSubmenu? {
        if let targetWindow = viewModel.commandKTargetWindow {
            return .actions(window: targetWindow)
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
            viewModel.requestLauncherFieldFocus()
            withAnimation(LauncherAnimation.submenuExit) {
                isPresented = false
            }
            return
        }

        displayedSubmenu = requestedSubmenu
        if isPresented {
            viewModel.requestSubmenuFieldFocus()
            return
        }
        withAnimation(LauncherAnimation.submenu) {
            isPresented = true
        }
        viewModel.requestSubmenuFieldFocus()
    }
}

struct LauncherActionMenuView: View {
    @ObservedObject var viewModel: LauncherViewModel
    let window: WindowEntry
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    private var actionItems: [ActionMenuItem] {
        viewModel.commandKActions.enumerated().map { index, action in
            ActionMenuItem(index: index, action: action)
        }
    }
    
    var body: some View {
        LauncherSubmenuPanel {
            VStack(spacing: 0) {
                LauncherSubmenuHeader {
                    LauncherSubmenuWindowHeader(window: window)
                }

                LauncherSubmenuSeparator()

                if actionItems.isEmpty {
                    Text(String(localized: "No actions found"))
                        .font(LauncherTypography.submenuRow)
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LauncherLayout.submenuRowHorizontalPadding)
                        .frame(height: LauncherLayout.submenuRowHeight)
                } else {
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

                LauncherSubmenuSeparator()
                LauncherSubmenuSearchField(
                    viewModel: viewModel,
                    kind: .actions,
                    placeholder: String(localized: "Search for actions...")
                )
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

    private var showsDisplayName: Bool {
        Set(viewModel.currentSpaces.map(\.displayID)).count > 1
    }

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
                    Text(String(localized: "No spaces found"))
                        .font(LauncherTypography.submenuRow)
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LauncherLayout.submenuRowHorizontalPadding)
                        .frame(height: LauncherLayout.submenuRowHeight)
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
                                        showDisplayName: showsDisplayName,
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

                LauncherSubmenuSeparator()
                LauncherSubmenuSearchField(
                    viewModel: viewModel,
                    kind: .spaces,
                    placeholder: viewModel.stagingWindow != nil
                        ? String(localized: "Search target space...")
                        : String(localized: "Search spaces...")
                )
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
    let showDisplayName: Bool
    let colors: ThemeColors
    let action: () -> Void

    private var metadata: String {
        if space.isFullscreen {
            return showDisplayName
                ? String(format: String(localized: "%@ · Fullscreen"), space.displayName)
                : String(localized: "Fullscreen")
        }

        return showDisplayName
            ? String(format: String(localized: "%@ · Space %lld"), space.displayName, space.num)
            : String(format: String(localized: "Space %lld"), space.num)
    }

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
                        symbolSize: LauncherLayout.submenuIconSymbolSize,
                        slot: LauncherLayout.submenuIconSlot
                    )
                }

                Text(space.name)
                    .font(LauncherTypography.submenuRow)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: LauncherLayout.submenuRowContentSpacing)

                LauncherTrailingLabel(
                    metadata,
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
    let action: LauncherCommandKAction

    var id: String {
        "\(index)-\(action.description)"
    }
}

struct CommandKActionRowView: View {
    let action: LauncherCommandKAction
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
                    symbolSize: LauncherLayout.submenuIconSymbolSize,
                    slot: LauncherLayout.submenuIconSlot
                )

                Text(viewModel.commandKActionLabel(action))
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
    
    private func getIconName(for action: LauncherCommandKAction) -> String {
        switch action {
        case .moveWindow: return "arrow.right"
        case .moveWindowTo: return "arrow.right.square"
        case .window(let action):
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
    }
    
}
