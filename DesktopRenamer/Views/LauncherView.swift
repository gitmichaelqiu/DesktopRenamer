import SwiftUI
import AppKit

struct ThemeColors {
    let isDark: Bool
    
    var backgroundOverlay: Color {
        isDark
            ? Color(red: 0.12, green: 0.13, blue: 0.15).opacity(0.72)
            : Color.white.opacity(0.72)
    }
    
    var textPrimary: Color {
        .primary
    }
    
    var textSecondary: Color {
        .secondary
    }
    
    var textTertiary: Color {
        .secondary.opacity(0.65)
    }
    
    var textQuaternary: Color {
        .secondary.opacity(0.4)
    }
    
    var border: Color {
        Color(nsColor: .separatorColor)
    }
    
    var rowHover: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
    }
    
    var badgeBg: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
    
    var badgeBorder: Color {
        Color.primary.opacity(0.08)
    }
    
    var separator: Color {
        Color(nsColor: .separatorColor)
    }
    
    var bottomBarBg: Color {
        isDark ? Color.black.opacity(0.16) : Color.white.opacity(0.26)
    }
    
    var greenText: Color {
        Color.green
    }
}

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var spaceManager = AppDelegate.shared.spaceManager!
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    private var isSpacePickerPresented: Bool {
        viewModel.isBottomBarFocused || viewModel.stagingWindow != nil
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header (Typing Bar)
                HStack(spacing: 14) {
                    Button(action: {
                        if viewModel.activeCommand != nil || viewModel.stagingWindow != nil {
                            viewModel.handleEscapeKey()
                        }
                    }) {
                        Image(systemName: viewModel.activeCommand == nil && viewModel.stagingWindow == nil ? "sparkles" : "chevron.left")
                            .foregroundColor(colors.textSecondary)
                            .font(.system(size: 22, weight: .medium))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.activeCommand == nil && viewModel.stagingWindow == nil)
                    
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
                            placeholder: NSLocalizedString("New Space Name...", comment: "")
                        )
                        .frame(height: 42)
                    } else {
                        SearchTextField(
                            text: $viewModel.searchQuery,
                            isDark: colors.isDark,
                            isTypingDisabled: viewModel.commandKTargetWindow != nil,
                            onUpArrow: {
                                if viewModel.commandKTargetWindow != nil {
                                    viewModel.selectPreviousCommandKAction()
                                } else if viewModel.stagingWindow != nil {
                                    viewModel.selectedSpaceIndex = max(0, viewModel.selectedSpaceIndex - 1)
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
                                } else if viewModel.stagingWindow != nil {
                                    let count = spaceManager.currentDisplaySpaces.count
                                    if viewModel.selectedSpaceIndex < count - 1 {
                                        viewModel.selectedSpaceIndex += 1
                                    }
                                } else {
                                    viewModel.isKeyboardSelection = true
                                    if viewModel.selectedRowIndex < viewModel.visibleRowsCount - 1 {
                                        viewModel.selectedRowIndex += 1
                                    }
                                }
                            },
                            onLeftArrow: {
                                if viewModel.commandKTargetWindow != nil {
                                    return true
                                }
                                if viewModel.isBottomBarFocused {
                                    if viewModel.selectedSpaceIndex > 0 {
                                        viewModel.selectedSpaceIndex -= 1
                                    }
                                    return true
                                }
                                return false
                            },
                            onRightArrow: {
                                if viewModel.commandKTargetWindow != nil {
                                    return true
                                }
                                if viewModel.isBottomBarFocused {
                                    let count = spaceManager.currentDisplaySpaces.count
                                    if viewModel.selectedSpaceIndex < count - 1 {
                                        viewModel.selectedSpaceIndex += 1
                                    }
                                    return true
                                }
                                return false
                            },
                            onEnter: {
                                if viewModel.commandKTargetWindow != nil {
                                    viewModel.executeCommandKAction()
                                } else if viewModel.stagingWindow != nil {
                                    viewModel.selectedRowIndex = viewModel.selectedSpaceIndex
                                    viewModel.executeRowAction()
                                } else if viewModel.isBottomBarFocused {
                                    viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: false)
                                } else {
                                    viewModel.executeRowAction()
                                }
                            },
                            onCommandEnter: {
                                if viewModel.commandKTargetWindow != nil {
                                    viewModel.executeCommandKAction()
                                } else if viewModel.stagingWindow != nil {
                                    viewModel.selectedRowIndex = viewModel.selectedSpaceIndex
                                    viewModel.executeRowAction()
                                } else if viewModel.isBottomBarFocused {
                                    viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: true)
                                } else if viewModel.activeCommand?.type == .batchMoveWindows {
                                    viewModel.executeBatchMove()
                                } else if viewModel.activeCommand?.type == .switchToDesktop || viewModel.activeCommand?.type == .moveWindow {
                                    viewModel.executeRowAction()
                                }
                            },
                            onOptionEnter: {
                                if viewModel.commandKTargetWindow != nil { return }
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
                                } else if viewModel.stagingWindow != nil {
                                    let index = num - 1
                                    let count = spaceManager.currentDisplaySpaces.count
                                    if index >= 0 && index < count {
                                        viewModel.selectedSpaceIndex = index
                                        viewModel.selectedRowIndex = index
                                        viewModel.executeRowAction()
                                    }
                                } else {
                                    viewModel.executeNthRowAction(num - 1)
                                }
                            },
                            onTab: {
                                if viewModel.commandKTargetWindow != nil { return }
                                viewModel.handleTabKey()
                            },
                            onEscape: {
                                if viewModel.commandKTargetWindow != nil {
                                    viewModel.commandKTargetWindow = nil
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
                            placeholder: viewModel.activeCommand == nil ? NSLocalizedString("Search commands...", comment: "") : (viewModel.stagingWindow != nil ? NSLocalizedString("Search target space...", comment: "") : NSLocalizedString("Search items...", comment: ""))
                        )
                        .frame(height: 42)
                    }
                    
                    if viewModel.isLoadingData {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    }
                }
                .frame(height: 72)
                .padding(.horizontal, 22)
                
                Divider()
                
                // Content area
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
                
                Divider()
                
                // Bottom bar
                if viewModel.activeCommand == nil {
                    SpacesBottomBar(viewModel: viewModel, spaceManager: spaceManager)
                } else if viewModel.activeCommand?.type == .batchMoveWindows {
                    BatchMoveBottomBar(viewModel: viewModel)
                } else {
                    CommandBottomBar(viewModel: viewModel)
                }
            }
            .blur(radius: viewModel.commandKTargetWindow != nil || isSpacePickerPresented ? 10 : 0)
            .animation(.easeInOut(duration: 0.12), value: viewModel.commandKTargetWindow != nil || isSpacePickerPresented)
            
            if let targetWindow = viewModel.commandKTargetWindow {
                CommandKOverlayView(viewModel: viewModel, window: targetWindow)
            }

            if isSpacePickerPresented {
                SpacePickerOverlay(viewModel: viewModel, spaceManager: spaceManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(width: 760, height: 500)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .launcherBackground(cornerRadius: 24, borderColor: colors.border)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.20), radius: 24, x: 0, y: 12)
        .padding(40)
    }
}

struct ListAreaView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.activeCommand == nil {
                // Main command list
                let commands = viewModel.filteredCommands
                if commands.isEmpty {
                    EmptyResultsView()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(0..<commands.count, id: \.self) { i in
                                    let cmd = commands[i]
                                    let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == i
                                    CommandRowView(command: cmd, isSelected: isSelected, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && i < 9 ? "⌘\(i + 1)" : nil)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            viewModel.isKeyboardSelection = true
                                            viewModel.selectedRowIndex = i
                                            viewModel.executeRowAction()
                                        }
                                        .id(i)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .onChange(of: viewModel.selectedRowIndex) { index in
                            if viewModel.isKeyboardSelection {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    proxy.scrollTo(index, anchor: .center)
                                }
                            }
                        }
                    }
                }
            } else {
                if viewModel.stagingWindow != nil && viewModel.activeCommand?.type != .listWindows {
                    // Staging target space selection
                    let spaces = viewModel.filteredSpaces
                    if spaces.isEmpty {
                        EmptyResultsView()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 4) {
                                    ForEach(0..<spaces.count, id: \.self) { i in
                                        let space = spaces[i]
                                        let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == i
                                        SpaceRowView(space: space, isSelected: isSelected, isCurrent: AppDelegate.shared.spaceManager?.currentSpaceUUID == space.id, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && i < 9 ? "⌘\(i + 1)" : nil)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                viewModel.isKeyboardSelection = true
                                                viewModel.selectedRowIndex = i
                                                viewModel.executeRowAction()
                                            }
                                            .id(i)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            }
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
                } else {
                    switch viewModel.activeCommand?.type {
                    case .switchToDesktop, .moveWindow:
                        let spaces = viewModel.filteredSpaces
                        if spaces.isEmpty {
                            EmptyResultsView()
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(spacing: 4) {
                                        ForEach(0..<spaces.count, id: \.self) { i in
                                            let space = spaces[i]
                                            let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == i
                                            SpaceRowView(space: space, isSelected: isSelected, isCurrent: AppDelegate.shared.spaceManager?.currentSpaceUUID == space.id, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && i < 9 ? "⌘\(i + 1)" : nil)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    viewModel.isKeyboardSelection = true
                                                    viewModel.selectedRowIndex = i
                                                    viewModel.executeRowAction()
                                                }
                                                .id(i)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                }
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
                        
                    case .listWindows:
                        let sections = viewModel.listWindowsSections
                        if sections.isEmpty {
                            EmptyResultsView()
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
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
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                }
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
                                    VStack(alignment: .leading, spacing: 4) {
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
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                }
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
                .background(colors.badgeBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
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
                        .fill(isSelected ? Color.primary.opacity(0.16) : Color.clear)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.primary.opacity(0.10) : Color.clear, lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(colors.rowHover)
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
                let appIcon = NSWorkspace.shared.icon(forFile: appPath)
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(colors.badgeBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                        .fill(isSelected ? Color.primary.opacity(0.16) : Color.clear)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.primary.opacity(0.10) : Color.clear, lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(colors.rowHover)
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
            let appIcon = NSWorkspace.shared.icon(forFile: window.appPath)
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                        .fill(isSelected ? Color.primary.opacity(0.16) : Color.clear)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.primary.opacity(0.10) : Color.clear, lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(colors.rowHover)
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
            let appIcon = NSWorkspace.shared.icon(forFile: window.appPath)
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                        .fill(isSelected ? Color.primary.opacity(0.16) : Color.clear)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.primary.opacity(0.10) : Color.clear, lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(colors.rowHover)
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

struct BatchMoveBottomBar: View {
    @ObservedObject var viewModel: LauncherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Left side: Active command hierarchy matching Raycast look
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.activeCommand?.iconName ?? "macwindow.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color.accentColor)
                    Text(viewModel.activeCommand?.title ?? String(localized: "Batch Move Windows"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(colors.textPrimary)
                }
                .modifier(BottomBarCapsule(isSelected: false, isActive: true, colorScheme: colorScheme))
                
                if let staging = viewModel.stagingWindow {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(colors.textQuaternary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(colors.greenText)
                        Text(String(format: NSLocalizedString("Stage: %@", comment: ""), staging.ownerName))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(colors.textPrimary)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                }
            }
            
            Spacer()
            
            // Right side: Context-sensitive actions
            HStack(spacing: 8) {
                if viewModel.stagingWindow != nil {
                    // Staging target space selection
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Stage"))
                        Text("↵")
                            .font(.system(.caption2))
                            .fontWeight(.bold)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.executeRowAction()
                    }
                } else {
                    // Selecting an item in batch move
                    let items = viewModel.batchMoveSelectableItems
                    let index = viewModel.selectedRowIndex
                    
                    if index >= 0 && index < items.count {
                        let selectedItem = items[index]
                        switch selectedItem {
                        case .staged(let action, _):
                            let isMove = {
                                if case .move = action.actionType { return true }
                                return false
                            }()
                            
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Text(verbatim: String(localized: isMove ? "Unstage Move" : "Unstage Action"))
                                    Text("↵")
                                        .font(.system(.subheadline))
                                        .fontWeight(.bold)
                                }
                                .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.executeRowAction()
                                }
                            }
                            
                        case .unstaged:
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Text(verbatim: String(localized: "Move to..."))
                                    Text("↵")
                                        .font(.system(.subheadline))
                                        .fontWeight(.bold)
                                }
                                .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.executeRowAction()
                                }
                                
                                HStack(spacing: 4) {
                                    Text(verbatim: String(localized: "Actions"))
                                    Text("⌘K")
                                        .font(.system(.subheadline))
                                        .fontWeight(.bold)
                                }
                                .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.showCommandKPanel()
                                }
                            }
                        }
                    }
                    
                    // If there are staged moves, show run batch action
                    if !viewModel.stagedMoves.isEmpty {
                        HStack(spacing: 4) {
                            Text(verbatim: String(localized: "Run Batch Actions"))
                            Text("⌘↵")
                                .font(.system(.subheadline))
                                .fontWeight(.bold)
                        }
                        .modifier(BottomBarCapsule(isSelected: true, isActive: false, isGreen: true, colorScheme: colorScheme))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.executeBatchMove()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(colors.bottomBarBg)
    }
}

struct SpacesBottomBar: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var spaceManager: SpaceManager
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: focusSpacePicker) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: String(localized: "Switch Space"))
                }
                .modifier(BottomBarCapsule(
                    isSelected: viewModel.isBottomBarFocused,
                    isActive: !viewModel.isBottomBarFocused,
                    colorScheme: colorScheme
                ))
            }
            .buttonStyle(.plain)

            Spacer()

            if viewModel.isBottomBarFocused {
                bottomBarAction(title: "Switch Space", shortcut: "↵") {
                    viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: false)
                }
                bottomBarAction(title: "Move Window", shortcut: "⌥↵") {
                    viewModel.executeBottomBarSpaceAction(isOption: true, isCommand: false)
                }
            } else {
                bottomBarAction(title: "Action", shortcut: "↵") {
                    viewModel.executeRowAction()
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(colors.bottomBarBg)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isBottomBarFocused)
    }

    private func focusSpacePicker() {
        viewModel.isBottomBarFocused = true
        viewModel.isKeyboardSelection = true

        let spaces = spaceManager.currentDisplaySpaces
        if let index = spaces.firstIndex(where: { $0.id == spaceManager.currentSpaceUUID }) {
            viewModel.selectedSpaceIndex = index
        } else {
            viewModel.selectedSpaceIndex = 0
        }
    }

    private func bottomBarAction(title: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(LocalizedStringKey(title))
                Text(shortcut)
                    .font(.system(.subheadline))
                    .fontWeight(.bold)
            }
            .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
        }
        .buttonStyle(.plain)
    }
}

struct SpacePickerOverlay: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var spaceManager: SpaceManager
    @Environment(\.colorScheme) var colorScheme

    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.handleEscapeKey()
                }

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: String(localized: "Switch Space"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(colors.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 4) {
                        let spaces = spaceManager.currentDisplaySpaces
                        ForEach(0..<spaces.count, id: \.self) { index in
                            let space = spaces[index]
                            Button(action: {
                                viewModel.selectedSpaceIndex = index
                                if viewModel.stagingWindow != nil {
                                    viewModel.selectedRowIndex = index
                                    viewModel.executeRowAction()
                                } else if NSEvent.modifierFlags.contains(.option) {
                                    viewModel.executeBottomBarSpaceAction(isOption: true, isCommand: false)
                                } else {
                                    viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: false)
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "rectangle.inset.filled")
                                        .font(.body.weight(.medium))
                                        .frame(width: 20)
                                    Text(spaceManager.getSpaceName(space.id))
                                        .font(.body.weight(.medium))
                                        .lineLimit(1)
                                    Spacer()
                                    if space.id == spaceManager.currentSpaceUUID {
                                        Text(verbatim: String(localized: "Current"))
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(colors.textTertiary)
                                    }
                                }
                                .foregroundColor(colors.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(index == viewModel.selectedSpaceIndex ? Color.primary.opacity(0.16) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
                .frame(maxHeight: 220)
            }
            .frame(width: 290)
            .spacePickerSurface(colors: colors)
            .padding(.trailing, 16)
            .padding(.bottom, 58)
        }
    }
}

struct CommandBottomBar: View {
    @ObservedObject var viewModel: LauncherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Left side: Active command pill matching Raycast look
            if let active = viewModel.activeCommand {
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: active.iconName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color.accentColor)
                        Text(active.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(colors.textPrimary)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: true, colorScheme: colorScheme))
                    
                    if let staging = viewModel.stagingWindow {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(colors.textQuaternary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(colors.greenText)
                            Text(String(format: NSLocalizedString("Move: %@", comment: ""), staging.ownerName))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(colors.textPrimary)
                        }
                        .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    }
                }
            }
            
            Spacer()
            
            // Right side: Context-sensitive actions
            if let type = viewModel.activeCommand?.type {
                switch type {
                case .switchToDesktop:
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Switch Space"))
                        Text("↵")
                            .font(.system(.subheadline))
                            .fontWeight(.bold)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.executeRowAction()
                    }

                case .moveWindow:
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Move Window"))
                        Text("↵")
                            .font(.system(.subheadline))
                            .fontWeight(.bold)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.executeRowAction()
                    }

                case .listWindows:
                    if viewModel.stagingWindow != nil {
                        HStack(spacing: 4) {
                            Text(verbatim: String(localized: "Move"))
                            Text("↵")
                                .font(.system(.subheadline))
                                .fontWeight(.bold)
                        }
                        .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.executeRowAction()
                        }
                    } else {
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Text(verbatim: String(localized: "Focus"))
                                Text("↵")
                                    .font(.system(.subheadline))
                                    .fontWeight(.bold)
                            }
                            .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.executeRowAction()
                            }
                            
                            HStack(spacing: 4) {
                                Text(verbatim: String(localized: "Move"))
                                Text("⌘M")
                                    .font(.system(.subheadline))
                                    .fontWeight(.bold)
                            }
                            .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let window = viewModel.selectedWindowForListWindows {
                                    viewModel.batchMoveLastSelectedIndex = viewModel.selectedRowIndex
                                    viewModel.stagingWindow = window
                                    viewModel.isExecutingRestoreToImmediately = true
                                    viewModel.selectedRowIndex = 0
                                }
                            }
                            
                            HStack(spacing: 4) {
                                Text(verbatim: String(localized: "Actions"))
                                Text("⌘K")
                                    .font(.system(.subheadline))
                                    .fontWeight(.bold)
                            }
                            .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.showCommandKPanel()
                            }
                        }
                    }

                case .renameCurrentSpace:
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Rename Space"))
                        Text("↵")
                            .font(.system(.subheadline))
                            .fontWeight(.bold)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.executeRowAction()
                    }
                    
                default:
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(colors.bottomBarBg)
    }
}

class FocusTextField: NSTextField {
    var onCommandEnter: (() -> Void)?
    var onOptionEnter: (() -> Void)?
    var onCommandNumber: ((Int) -> Void)?
    var onCommandK: (() -> Void)?
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var isTypingDisabled: Bool = false

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let handled = onKeyEquivalent?(event), handled {
            return true
        }
        
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommand = modifiers.contains(.command)
            let hasOption = modifiers.contains(.option)
            let hasOtherModifiers = !modifiers.subtracting([.command, .option, .numericPad, .function]).isEmpty
            
            if !hasOtherModifiers {
                if (hasCommand || hasOption) && (event.keyCode == 36 || event.keyCode == 76) {
                    if hasCommand {
                        onCommandEnter?()
                    } else if hasOption {
                        onOptionEnter?()
                    }
                    return true
                }
                
                if hasCommand {
                    if let chars = event.charactersIgnoringModifiers,
                       chars.count == 1,
                       let char = chars.first,
                       let number = Int(String(char)),
                       number >= 1 && number <= 9 {
                        onCommandNumber?(number)
                        return true
                    }
                    
                    if event.charactersIgnoringModifiers?.lowercased() == "k" {
                        onCommandK?()
                        return true
                    }
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(forceFocus), name: NSNotification.Name("FocusLauncherTextField"), object: nil)
            if window?.isKeyWindow == true {
                DispatchQueue.main.async { [weak self] in
                    self?.forceFocus()
                }
            }
        } else {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("FocusLauncherTextField"), object: nil)
        }
    }
    
    @objc private func windowDidBecomeKey() {
        DispatchQueue.main.async { [weak self] in
            self?.forceFocus()
        }
    }
    
    @objc private func forceFocus() {
        guard let window = self.window else { return }
        window.makeFirstResponder(self)
        self.currentEditor()?.selectAll(nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

class BlockTypingFormatter: Formatter {
    var isTypingDisabled: () -> Bool
    
    init(isTypingDisabled: @escaping () -> Bool) {
        self.isTypingDisabled = isTypingDisabled
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func string(for obj: Any?) -> String? {
        return obj as? String
    }
    
    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        obj?.pointee = string as AnyObject
        return true
    }
    
    override func isPartialStringValid(_ partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        if isTypingDisabled() {
            return false
        }
        return true
    }
}

struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    var isDark: Bool
    var isTypingDisabled: Bool = false
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void
    var onLeftArrow: (() -> Bool)? = nil
    var onRightArrow: (() -> Bool)? = nil
    var onEnter: () -> Void
    var onCommandEnter: (() -> Void)? = nil
    var onOptionEnter: (() -> Void)? = nil
    var onCommandNumber: ((Int) -> Void)? = nil
    var onTab: (() -> Void)? = nil
    var onEscape: () -> Void
    var onCommandK: (() -> Void)? = nil
    var onKeyEquivalent: ((NSEvent) -> Bool)? = nil
    var placeholder: String = "Type a command..."
    
    class Coordinator: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
        var parent: SearchTextField
        var lastPlaceholder: String? = nil
        var lastIsDark: Bool? = nil
        
        init(_ parent: SearchTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
        
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if parent.isTypingDisabled {
                return false
            }
            return true
        }
        
        func textView(_ textView: NSTextView, shouldChangeTextInRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
            if parent.isTypingDisabled {
                return false
            }
            return true
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onUpArrow()
                return true
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onDownArrow()
                return true
            } else if commandSelector == #selector(NSResponder.moveLeft(_:)) {
                if parent.onLeftArrow?() == true {
                    return true
                }
            } else if commandSelector == #selector(NSResponder.moveRight(_:)) {
                if parent.onRightArrow?() == true {
                    return true
                }
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) || commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                parent.onTab?()
                return true
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                let isCommandPressed = NSEvent.modifierFlags.contains(.command)
                let isOptionPressed = NSEvent.modifierFlags.contains(.option)
                if isCommandPressed, let onCommandEnter = parent.onCommandEnter {
                    onCommandEnter()
                } else if isOptionPressed, let onOptionEnter = parent.onOptionEnter {
                    onOptionEnter()
                } else {
                    parent.onEnter()
                }
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = FocusTextField()
        textField.delegate = context.coordinator
        
        let formatter = BlockTypingFormatter(isTypingDisabled: { [weak coordinator = context.coordinator] in
            coordinator?.parent.isTypingDisabled ?? false
        })
        textField.formatter = formatter
        
        // Route closures safely and dynamically through the coordinator
        textField.onCommandEnter = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onCommandEnter?()
        }
        textField.onOptionEnter = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onOptionEnter?()
        }
        textField.onCommandNumber = { [weak coordinator = context.coordinator] num in
            coordinator?.parent.onCommandNumber?(num)
        }
        textField.onCommandK = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onCommandK?()
        }
        textField.onKeyEquivalent = onKeyEquivalent
        textField.isTypingDisabled = isTypingDisabled
        
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = .labelColor
        textField.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        
        context.coordinator.lastPlaceholder = placeholder
        context.coordinator.lastIsDark = isDark
        
        let placeholderAttr = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: NSFont.systemFont(ofSize: 20, weight: .regular)
            ]
        )
        textField.placeholderAttributedString = placeholderAttr
        
        textField.stringValue = text
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        
        if let focusField = nsView as? FocusTextField {
            focusField.isTypingDisabled = isTypingDisabled
            focusField.onKeyEquivalent = onKeyEquivalent
        }
        
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.textColor = .labelColor
        
        // Cache placeholder creation to avoid recreating it on every render cycle
        if context.coordinator.lastPlaceholder != placeholder || context.coordinator.lastIsDark != isDark {
            context.coordinator.lastPlaceholder = placeholder
            context.coordinator.lastIsDark = isDark
            
            let placeholderAttr = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: NSColor.placeholderTextColor,
                    .font: NSFont.systemFont(ofSize: 20, weight: .regular)
                ]
            )
            nsView.placeholderAttributedString = placeholderAttr
        }
    }
}

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

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

extension View {
    @ViewBuilder
    func launcherBackground(cornerRadius: CGFloat, borderColor: Color) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    func spacePickerSurface(colors: ThemeColors) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(colors.border.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        } else {
            self
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(colors.border.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
    }
}

struct BottomBarCapsule: ViewModifier {
    let isSelected: Bool
    let isActive: Bool
    var isGreen: Bool = false
    let colorScheme: ColorScheme
    
    @State private var isHovered: Bool = false
    
    var greenBgColor: Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.48, blue: 0.26) : Color(red: 0.12, green: 0.44, blue: 0.22)
    }
    
    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .fontWeight(isSelected || isActive ? .semibold : .medium)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                ZStack {
                    if isGreen {
                        if isSelected {
                            greenBgColor.opacity(isHovered ? 0.9 : 1.0)
                        } else if isActive {
                            greenBgColor.opacity(isHovered ? 0.25 : 0.15)
                        } else {
                            Color.primary.opacity(isHovered ? 0.12 : 0.06)
                        }
                    } else {
                        if isSelected {
                            isActive ? Color.primary.opacity(0.24) : Color.primary.opacity(0.16)
                        } else if isActive {
                            Color.primary.opacity(isHovered ? 0.22 : 0.14)
                        } else {
                            Color.primary.opacity(isHovered ? 0.12 : 0.06)
                        }
                    }
                }
            )
            .foregroundColor(
                isGreen ? (isSelected ? .white : (isActive ? greenBgColor : (isHovered ? greenBgColor : .secondary)))
                        : (isActive ? .primary : (isSelected || isHovered ? .primary : .secondary))
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isGreen ? (isSelected ? Color.primary.opacity(0.15) : (isActive ? greenBgColor.opacity(isHovered ? 0.4 : 0.2) : Color.primary.opacity(isHovered ? 0.25 : 0.08)))
                                : (isSelected ? (isActive ? Color.primary.opacity(0.48) : Color.primary.opacity(0.40)) : (isActive ? Color.primary.opacity(isHovered ? 0.35 : 0.22) : Color.primary.opacity(isHovered ? 0.25 : 0.08))),
                        lineWidth: (isSelected && !isGreen) ? 1.5 : 1
                    )
            )
            .shadow(color: isSelected ? (isGreen ? greenBgColor.opacity(0.25) : Color.primary.opacity(0.1)) : Color.clear, radius: 3, x: 0, y: 1)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 210
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension LauncherView {
    private func handleTextFieldKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = modifiers.contains(.command)
        let hasShift = modifiers.contains(.shift)
        let hasOption = modifiers.contains(.option)
        let hasControl = modifiers.contains(.control)
        
        // Direct window shortcuts for .listWindows (cmd + m, cmd + shift + m/w/n/r/f/h/q)
        if viewModel.activeCommand?.type == .listWindows,
           viewModel.commandKTargetWindow == nil,
           viewModel.stagingWindow == nil {
            
            let windows = viewModel.filteredWindows
            let index = viewModel.selectedRowIndex
            if index >= 0 && index < windows.count {
                let window = windows[index]
                
                if hasCommand && !hasOption && !hasControl {
                    if let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1 {
                        let char = chars.first!
                        
                        if char == "m" && !hasShift {
                            // cmd + m: Move to Desktop... (show space selector)
                            viewModel.batchMoveLastSelectedIndex = viewModel.selectedRowIndex
                            viewModel.stagingWindow = window
                            viewModel.isExecutingRestoreToImmediately = true
                            viewModel.selectedRowIndex = 0
                            return true
                        } else if hasShift {
                            switch char {
                            case "w":
                                // cmd + shift + w: Close Window
                                viewModel.executeActionImmediately(window: window, actionType: .close)
                                return true
                            case "m":
                                // cmd + shift + m: Minimize Window
                                viewModel.executeActionImmediately(window: window, actionType: .minimize)
                                return true
                            case "r":
                                // cmd + shift + r: Restore Window
                                viewModel.executeActionImmediately(window: window, actionType: .restore)
                                return true
                            case "f":
                                // cmd + shift + f: Toggle Full Screen
                                let isFS = window.space.isFullscreen
                                let action: BatchStagedActionType = isFS ? .exitFullScreen : .enterFullScreen
                                viewModel.executeActionImmediately(window: window, actionType: action)
                                return true
                            case "h":
                                // cmd + shift + h: Hide Application
                                viewModel.executeActionImmediately(window: window, actionType: .hide)
                                return true
                            case "q":
                                // cmd + shift + q: Quit Application
                                viewModel.executeActionImmediately(window: window, actionType: .quit)
                                return true
                            default:
                                break
                            }
                        }
                    }
                }
            }
        }

        // Cmd+R: Rename selected space in .switchToDesktop mode
        if viewModel.activeCommand?.type == .switchToDesktop,
           hasCommand && !hasShift && !hasOption && !hasControl,
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "r" {
            let spaces = viewModel.filteredSpaces
            let index = viewModel.selectedRowIndex
            if index >= 0 && index < spaces.count {
                let space = spaces[index]
                if !space.isFullscreen {
                    viewModel.showRenameDialog(for: space)
                }
            }
            return true
        }

        return false
    }
}
