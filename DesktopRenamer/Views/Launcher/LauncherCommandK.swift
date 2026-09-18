import SwiftUI

private enum LauncherSubmenu {
    case actions(window: WindowEntry, fallbackActions: [LauncherCommandKAction])
    case spaces(
        fallbackSpaces: [SpaceGroup],
        fallbackStagingWindow: WindowEntry?,
        fallbackTitle: String,
        isTargetSpaceSelection: Bool
    )
}

struct LauncherSubmenuOverlay: View {
    @ObservedObject var viewModel: LauncherViewModel

    @State private var displayedSubmenu: LauncherSubmenu = .spaces(
        fallbackSpaces: [],
        fallbackStagingWindow: nil,
        fallbackTitle: "",
        isTargetSpaceSelection: false
    )
    @State private var displayedSubmenuKey = "none"
    @State private var isPresented = false
    @State private var presentationGeneration = 0

    private var requestedSubmenu: LauncherSubmenu? {
        if let targetWindow = viewModel.commandKTargetWindow {
            return .actions(
                window: targetWindow,
                fallbackActions: viewModel.commandKActions
            )
        }
        if viewModel.isSpaceMenuOpen {
            return .spaces(
                fallbackSpaces: viewModel.spaceMenuSpaces,
                fallbackStagingWindow: viewModel.stagingWindow,
                fallbackTitle: viewModel.activeCommand?.title ?? String(localized: "Select Space"),
                isTargetSpaceSelection: viewModel.stagingWindow != nil
            )
        }
        return nil
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
        case .actions(let window, let fallbackActions):
            LauncherActionMenuView(
                viewModel: viewModel,
                window: window,
                fallbackActions: fallbackActions
            )
        case .spaces(let fallbackSpaces, let fallbackStagingWindow, let fallbackTitle, let isTargetSpaceSelection):
            LauncherSpaceMenuView(
                viewModel: viewModel,
                fallbackSpaces: fallbackSpaces,
                fallbackStagingWindow: fallbackStagingWindow,
                fallbackTitle: fallbackTitle,
                fallbackIsTargetSpaceSelection: isTargetSpaceSelection
            )
        }
    }

    private func synchronizeSubmenu() {
        guard let requestedSubmenu else {
            presentationGeneration &+= 1
            viewModel.requestLauncherFieldFocus()
            if isPresented {
                withAnimation(LauncherAnimation.submenuExit) {
                    isPresented = false
                }
            }
            return
        }

        let requestedKey = requestedSubmenuKey
        guard isPresented else {
            displayedSubmenu = requestedSubmenu
            displayedSubmenuKey = requestedKey
            withAnimation(LauncherAnimation.submenu) {
                isPresented = true
            }
            viewModel.requestSubmenuFieldFocus()
            return
        }

        guard displayedSubmenuKey != requestedKey else {
            viewModel.requestSubmenuFieldFocus()
            return
        }

        presentationGeneration &+= 1
        let generation = presentationGeneration
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPresented = false
            displayedSubmenu = requestedSubmenu
            displayedSubmenuKey = requestedKey
        }

        DispatchQueue.main.async { [viewModel] in
            guard generation == presentationGeneration,
                  viewModel.isSubmenuOpen,
                  displayedSubmenuKey == requestedKey else {
                return
            }
            withAnimation(LauncherAnimation.submenuSwap) {
                isPresented = true
            }
            viewModel.requestSubmenuFieldFocus()
        }
    }
}

struct LauncherActionMenuView: View {
    @ObservedObject var viewModel: LauncherViewModel
    let window: WindowEntry
    let fallbackActions: [LauncherCommandKAction]
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    private var actionItems: [ActionMenuItem] {
        let actions = viewModel.commandKTargetWindow == nil
            ? fallbackActions
            : viewModel.commandKActions
        return actions.enumerated().map { index, action in
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
                                idx: item.index,
                                shortcutNumber: viewModel.shouldShowCommandNumbersInSubmenu && item.index < 9
                                    ? item.index + 1
                                    : nil,
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
    let fallbackSpaces: [SpaceGroup]
    let fallbackStagingWindow: WindowEntry?
    let fallbackTitle: String
    let fallbackIsTargetSpaceSelection: Bool
    @Environment(\.colorScheme) var colorScheme

    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    private var spaces: [SpaceGroup] {
        viewModel.isSpaceMenuOpen ? viewModel.spaceMenuSpaces : fallbackSpaces
    }

    private var showsDisplayName: Bool {
        viewModel.shouldShowDisplayNameForSpaces
    }

    private var title: String {
        viewModel.activeCommand?.title ?? fallbackTitle
    }

    private var stagingWindow: WindowEntry? {
        viewModel.stagingWindow ?? fallbackStagingWindow
    }

    private var isTargetSpaceSelection: Bool {
        fallbackIsTargetSpaceSelection || stagingWindow != nil
    }

    var body: some View {
        LauncherSubmenuPanel {
            VStack(alignment: .leading, spacing: 0) {
                LauncherSubmenuHeader {
                    if let stagingWindow {
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
                                        showShortcut: viewModel.shouldShowCommandNumbersInSubmenu && index < 9,
                                        showDisplayName: showsDisplayName,
                                        colors: colors,
                                        ignoresHover: viewModel.isKeyboardSelection,
                                        action: {
                                            viewModel.isKeyboardSelection = true
                                            viewModel.spaceMenuSelectedIndex = index
                                            viewModel.executeSpaceMenuSelection()
                                            viewModel.finishPointerAction()
                                        }
                                    )
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
                    placeholder: isTargetSpaceSelection
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
    let ignoresHover: Bool
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
        LauncherSubmenuRow(
            isSelected: isSelected,
            commandNumber: showShortcut ? shortcutNumber : nil,
            ignoresHover: ignoresHover,
            action: action
        ) {
            HStack(spacing: LauncherLayout.submenuRowContentSpacing) {
                if isCurrent {
                    Circle()
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(
                            width: LauncherLayout.submenuActionIconSlot,
                            height: LauncherLayout.submenuActionIconSlot
                        )
                } else {
                    LauncherIconSlot(
                        systemName: "desktopcomputer",
                        tint: colors.textPrimary,
                        symbolSize: LauncherLayout.submenuActionIconSymbolSize,
                        slot: LauncherLayout.submenuActionIconSlot
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
                .padding(
                    .trailing,
                    showShortcut
                        ? LauncherLayout.commandNumberIndicatorWidth
                            + LauncherLayout.commandNumberIndicatorTrailingGap
                        : 0
                )
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
    let idx: Int
    let shortcutNumber: Int?
    let colors: ThemeColors
    @ObservedObject var viewModel: LauncherViewModel
    
    var body: some View {
        LauncherSubmenuRow(
            isSelected: isSelected,
            commandNumber: shortcutNumber,
            ignoresHover: viewModel.isKeyboardSelection,
            action: {
                viewModel.commandKSelectedIndex = idx
                viewModel.executeCommandKAction()
                viewModel.finishPointerAction()
            }
        ) {
            HStack(spacing: LauncherLayout.submenuRowContentSpacing) {
                LauncherIconSlot(
                    systemName: getIconName(for: action),
                    tint: colors.textPrimary,
                    symbolSize: LauncherLayout.submenuActionIconSymbolSize,
                    slot: LauncherLayout.submenuActionIconSlot
                )

                Text(viewModel.commandKActionLabel(action))
                    .font(LauncherTypography.submenuRow)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if !action.shortcutText.isEmpty {
                    KeycapView(text: action.shortcutText, isSelected: isSelected)
                        .padding(
                            .trailing,
                            shortcutNumber == nil
                                ? 0
                                : LauncherLayout.commandNumberIndicatorWidth
                                    + LauncherLayout.commandNumberIndicatorTrailingGap
                        )
                }
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
