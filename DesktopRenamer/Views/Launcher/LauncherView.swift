import SwiftUI
import AppKit

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var spaceManager = AppDelegate.shared.spaceManager!
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header (Typing Bar)
                HStack(spacing: 0) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(colors.textSecondary)
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 22, height: 22)
                        .padding(.trailing, 8)
                    
                    if viewModel.activeCommand?.type == .renameCurrentSpace {
                        SearchTextField(
                            text: $viewModel.renameInputText,
                            isDark: colors.isDark,
                            onUpArrow: {},
                            onDownArrow: {},
                            onEnter: {
                                viewModel.executeRowAction()
                            },
                            onEscape: {
                                viewModel.handleEscapeKey()
                            },
                            onKeyEquivalent: { _ in false },
                            placeholder: NSLocalizedString("New Space Name...", comment: ""),
                            textFieldFont: NSFont.systemFont(ofSize: 20, weight: .regular),
                            textFieldColor: .labelColor,
                            placeholderColor: .placeholderTextColor,
                            usesSingleLineMode: true
                        )
                        .frame(height: 36)
                    } else {
                        SearchTextField(
                            text: $viewModel.searchQuery,
                            isDark: colors.isDark,
                            isTypingDisabled: viewModel.commandKTargetWindow != nil,
                            onUpArrow: {
                                if viewModel.commandKTargetWindow != nil {
                                    viewModel.selectPreviousCommandKAction()
                                } else if viewModel.isSpaceMenuOpen {
                                    viewModel.isKeyboardSelection = true
                                    viewModel.spaceMenuSelectedIndex = max(viewModel.spaceMenuSelectedIndex - 1, 0)
                                } else {
                                    viewModel.isKeyboardSelection = true
                                    if viewModel.selectedRowIndex > 0 {
                                        viewModel.selectedRowIndex -= 1
                                    }
                                }
                            },
                            onDownArrow: {
                                if viewModel.commandKTargetWindow != nil {
                                    viewModel.selectNextCommandKAction()
                                } else if viewModel.isSpaceMenuOpen {
                                    viewModel.isKeyboardSelection = true
                                    viewModel.spaceMenuSelectedIndex = min(
                                        viewModel.spaceMenuSelectedIndex + 1,
                                        max(viewModel.spaceMenuSpaces.count - 1, 0)
                                    )
                                } else {
                                    viewModel.isKeyboardSelection = true
                                    if viewModel.selectedRowIndex < viewModel.visibleRowsCount - 1 {
                                        viewModel.selectedRowIndex += 1
                                    }
                                }
                            },
                            onLeftArrow: {
                                if viewModel.commandKTargetWindow != nil || viewModel.isSpaceMenuOpen {
                                    return true
                                }
                                if viewModel.isBottomBarFocused {
                                    viewModel.moveSpaceSelection(by: -1)
                                    return true
                                }
                                if viewModel.searchQuery.isEmpty {
                                    viewModel.focusSpaceBar(movingBy: -1)
                                    return true
                                }
                                return false
                            },
                            onRightArrow: {
                                if viewModel.commandKTargetWindow != nil || viewModel.isSpaceMenuOpen {
                                    return true
                                }
                                if viewModel.isBottomBarFocused {
                                    viewModel.moveSpaceSelection(by: 1)
                                    return true
                                }
                                if viewModel.searchQuery.isEmpty {
                                    viewModel.focusSpaceBar(movingBy: 1)
                                    return true
                                }
                                return false
                            },
                            onEnter: {
                                if viewModel.commandKTargetWindow != nil {
                                    viewModel.executeCommandKAction()
                                } else if viewModel.isSpaceMenuOpen {
                                    viewModel.executeSpaceMenuSelection()
                                } else if viewModel.isBottomBarFocused {
                                    viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: false)
                                } else {
                                    viewModel.executeRowAction()
                                }
                            },
                            onCommandEnter: {
                                if viewModel.commandKTargetWindow != nil {
                                    viewModel.executeCommandKAction()
                                } else if viewModel.isSpaceMenuOpen {
                                    viewModel.executeSpaceMenuSelection()
                                } else if viewModel.isBottomBarFocused {
                                    viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: true)
                                } else if viewModel.activeCommand?.type == .batchMoveWindows {
                                    viewModel.executeBatchMove()
                                } else if viewModel.activeCommand?.type == .switchToDesktop || viewModel.activeCommand?.type == .moveWindow {
                                    viewModel.executeRowAction()
                                }
                            },
                            onOptionEnter: {
                                if viewModel.commandKTargetWindow != nil || viewModel.isSpaceMenuOpen { return }
                                if viewModel.isBottomBarFocused {
                                    viewModel.executeBottomBarSpaceAction(isOption: true, isCommand: false)
                                }
                            },
                            onCommandNumber: { num in
                                if viewModel.commandKTargetWindow != nil {
                                    let actions = viewModel.commandKActions
                                    let index = num - 1
                                    if index >= 0 && index < actions.count {
                                        viewModel.commandKSelectedIndex = index
                                        viewModel.executeCommandKAction()
                                    }
                                } else if viewModel.isSpaceMenuOpen {
                                    let index = num - 1
                                    if viewModel.spaceMenuSpaces.indices.contains(index) {
                                        viewModel.spaceMenuSelectedIndex = index
                                        viewModel.executeSpaceMenuSelection()
                                    }
                                } else {
                                    viewModel.executeNthRowAction(num - 1)
                                }
                            },
                            onTab: {
                                if viewModel.commandKTargetWindow != nil || viewModel.isSpaceMenuOpen { return }
                                viewModel.handleTabKey()
                            },
                            onEscape: {
                                if viewModel.commandKTargetWindow != nil {
                                    viewModel.commandKTargetWindow = nil
                                } else if viewModel.isSpaceMenuOpen {
                                    viewModel.handleEscapeKey()
                                } else {
                                    viewModel.handleEscapeKey()
                                }
                            },
                            onCommandK: {
                                if viewModel.commandKTargetWindow != nil {
                                    viewModel.commandKTargetWindow = nil
                                } else if (viewModel.activeCommand?.type == .batchMoveWindows || viewModel.activeCommand?.type == .listWindows) && viewModel.stagingWindow == nil {
                                    viewModel.showCommandKPanel()
                                }
                            },
                            onKeyEquivalent: { event in
                                return self.handleTextFieldKeyEquivalent(event)
                            },
                            placeholder: viewModel.activeCommand == nil ? NSLocalizedString("Search commands...", comment: "") : (viewModel.stagingWindow != nil ? NSLocalizedString("Search target space...", comment: "") : NSLocalizedString("Search items...", comment: "")),
                            textFieldFont: NSFont.systemFont(ofSize: 20, weight: .regular),
                            textFieldColor: .labelColor,
                            placeholderColor: .placeholderTextColor,
                            usesSingleLineMode: true
                        )
                        .frame(height: 36)
                    }
                    
                    if viewModel.isLoadingData {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // Keep the footer as a sibling of the list so the scroll view reserves its height.
                Group {
                if viewModel.activeCommand?.type == .renameCurrentSpace {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "pencil.line")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(.secondary)
                        
                        Text(verbatim: String(localized: "Rename Current Space"))
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
 
                        Text(verbatim: String(localized: "Type a new name above and press Enter to save"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
                } else if viewModel.isExecutingBatchMove {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(verbatim: String(localized: "Executing batch window moves..."))
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
                } else {
                    ListAreaView(viewModel: viewModel)
                        .frame(maxHeight: .infinity)
                }
                
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.activeCommand == nil {
                    SpacesBottomBar(viewModel: viewModel, spaceManager: spaceManager)
                } else if viewModel.activeCommand?.type == .batchMoveWindows {
                    BatchMoveBottomBar(viewModel: viewModel)
                } else {
                    CommandBottomBar(viewModel: viewModel)
                }
            }

            LauncherSubmenuOverlay(viewModel: viewModel)
        }
        .frame(width: 750, height: 475)
        .launcherBackground(cornerRadius: 26)
        .disabled(viewModel.isRearrangingSpace)
    }
}

struct ListAreaView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    var body: some View {
        let currentSpaceIDsByDisplay = SpaceHelper.getCurrentSpaceIDsByDisplay()

        VStack(spacing: 0) {
            let showsRootCommands = viewModel.activeCommand == nil || (
                viewModel.isSpaceMenuOpen &&
                (viewModel.activeCommand?.type == .switchToDesktop || viewModel.activeCommand?.type == .moveWindow)
            )

            if showsRootCommands {
                // Main command list
                let commands = viewModel.filteredCommands
                if commands.isEmpty {
                    EmptyResultsView()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(commands.enumerated()), id: \.element.id) { i, cmd in
                                    let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == i
                                    CommandRowView(command: cmd, isSelected: isSelected, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && i < 9 ? "⌘\(i + 1)" : nil)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            viewModel.isKeyboardSelection = true
                                            viewModel.selectedRowIndex = i
                                            viewModel.executeRowAction()
                                        }
                                        .id(cmd.id)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: viewModel.selectedRowIndex) { index in
                            if viewModel.isKeyboardSelection {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    guard commands.indices.contains(index) else { return }
                                    proxy.scrollTo(commands[index].id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            } else {
                if viewModel.stagingWindow != nil && !viewModel.isSpaceMenuOpen {
                    // Staging target space selection
                    let spaces = viewModel.filteredMoveWindowSpaces
                    if spaces.isEmpty {
                        EmptyResultsView()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(spaces.enumerated()), id: \.element.id) { i, space in
                                        let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == i
                                        let isCurrent = currentSpaceIDsByDisplay[space.displayID] == space.id
                                        SpaceRowView(space: space, isSelected: isSelected, isCurrent: isCurrent, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && i < 9 ? "⌘\(i + 1)" : nil)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                viewModel.isKeyboardSelection = true
                                                viewModel.selectedRowIndex = i
                                                viewModel.executeRowAction()
                                            }
                                            .id(space.id)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.top, 4)
                                .padding(.bottom, 8)
                            }
                            .scrollIndicators(.hidden)
                            .onChange(of: viewModel.selectedRowIndex) { index in
                                if viewModel.isKeyboardSelection {
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        guard spaces.indices.contains(index) else { return }
                                        proxy.scrollTo(spaces[index].id, anchor: .center)
                                    }
                                }
                            }
                            .onAppear {
                                if spaces.indices.contains(viewModel.selectedRowIndex) {
                                    proxy.scrollTo(spaces[viewModel.selectedRowIndex].id, anchor: .center)
                                }
                            }
                        }
                    }
                } else {
                    switch viewModel.activeCommand?.type {
                    case .switchToDesktop, .moveWindow:
                        let spaces = viewModel.activeCommand?.type == .moveWindow
                            ? viewModel.filteredActiveWindowMoveSpaces
                            : viewModel.filteredSpaces
                        if spaces.isEmpty {
                            EmptyResultsView()
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        ForEach(Array(spaces.enumerated()), id: \.element.id) { i, space in
                                            let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == i
                                            let isCurrent = currentSpaceIDsByDisplay[space.displayID] == space.id
                                            SpaceRowView(space: space, isSelected: isSelected, isCurrent: isCurrent, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && i < 9 ? "⌘\(i + 1)" : nil)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    viewModel.isKeyboardSelection = true
                                                    viewModel.selectedRowIndex = i
                                                    viewModel.executeRowAction()
                                                }
                                                .id(space.id)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.top, 4)
                                    .padding(.bottom, 8)
                                }
                                .scrollIndicators(.hidden)
                                .onChange(of: viewModel.selectedRowIndex) { index in
                                    if viewModel.isKeyboardSelection {
                                        withAnimation(.easeInOut(duration: 0.12)) {
                                            guard spaces.indices.contains(index) else { return }
                                            proxy.scrollTo(spaces[index].id, anchor: .center)
                                        }
                                    }
                                }
                                .onAppear {
                                if spaces.indices.contains(viewModel.selectedRowIndex) {
                                    proxy.scrollTo(spaces[viewModel.selectedRowIndex].id, anchor: .center)
                                }
                                }
                            }
                        }
                        
                    case .listWindows:
                        let sections = viewModel.listWindowsSections
                        if sections.isEmpty {
                            EmptyResultsView()
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        ForEach(0..<sections.count, id: \.self) { sIdx in
                                            let section = sections[sIdx]
                                            ListSectionHeader(title: section.title, subtitle: section.subtitle, isFirst: sIdx == 0)
                                            
                                            ForEach(section.items) { item in
                                                let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == item.index
                                                WindowRowView(
                                                    window: item.window,
                                                    isSelected: isSelected,
                                                    shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && item.index < 9 ? "⌘\(item.index + 1)" : nil
                                                )
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    viewModel.isKeyboardSelection = true
                                                    viewModel.selectedRowIndex = item.index
                                                    viewModel.executeRowAction()
                                                }
                                                .id(item.index)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.top, 4)
                                    .padding(.bottom, 8)
                                }
                                .scrollIndicators(.hidden)
                                .onChange(of: viewModel.selectedRowIndex) { index in
                                    if viewModel.isKeyboardSelection {
                                        withAnimation(.easeInOut(duration: 0.12)) {
                                            proxy.scrollTo(index, anchor: .center)
                                        }
                                    }
                                }
                                .onAppear {
                                    proxy.scrollTo(viewModel.selectedRowIndex, anchor: .center)
                                }
                            }
                        }
                        
                    case .batchMoveWindows:
                        let sections = viewModel.batchMoveSections
                        if sections.isEmpty {
                            EmptyResultsView()
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        ForEach(0..<sections.count, id: \.self) { sIdx in
                                            let section = sections[sIdx]
                                            ListSectionHeader(title: section.title, subtitle: section.subtitle, isFirst: sIdx == 0)
                                            
                                            ForEach(section.items) { item in
                                                let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == item.index
                                                
                                                switch item {
                                                case .staged(let move, _):
                                                    WindowBatchRowView(window: move.window, isSelected: isSelected, isStaged: true, stagedActionText: move.actionType.description, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && item.index < 9 ? "⌘\(item.index + 1)" : nil)
                                                        .contentShape(Rectangle())
                                                        .onTapGesture {
                                                            viewModel.isKeyboardSelection = true
                                                            viewModel.selectedRowIndex = item.index
                                                            viewModel.executeRowAction()
                                                        }
                                                        .id(item.index)
                                                        
                                                case .unstaged(let window, _):
                                                    WindowBatchRowView(window: window, isSelected: isSelected, isStaged: false, stagedActionText: "", shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && item.index < 9 ? "⌘\(item.index + 1)" : nil)
                                                        .contentShape(Rectangle())
                                                        .onTapGesture {
                                                            viewModel.isKeyboardSelection = true
                                                            viewModel.selectedRowIndex = item.index
                                                            viewModel.executeRowAction()
                                                        }
                                                        .id(item.index)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.top, 4)
                                    .padding(.bottom, 8)
                                }
                                .scrollIndicators(.hidden)
                                .onChange(of: viewModel.selectedRowIndex) { index in
                                    if viewModel.isKeyboardSelection {
                                        withAnimation(.easeInOut(duration: 0.12)) {
                                            proxy.scrollTo(index, anchor: .center)
                                        }
                                    }
                                }
                                .onAppear {
                                    DispatchQueue.main.async {
                                        proxy.scrollTo(viewModel.selectedRowIndex, anchor: .center)
                                    }
                                }
                            }
                        }
                        
                    default:
                        EmptyResultsView()
                    }
                }
            }
        }
    }
}
