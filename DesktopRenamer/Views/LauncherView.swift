import SwiftUI
import AppKit

struct ThemeColors {
    let isDark: Bool
    
    var backgroundOverlay: Color {
        Color.clear
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
        Color.primary.opacity(0.08)
    }
    
    var badgeBg: Color {
        Color.primary.opacity(0.06)
    }
    
    var badgeBorder: Color {
        Color.primary.opacity(0.08)
    }
    
    var separator: Color {
        Color(nsColor: .separatorColor)
    }
    
    var bottomBarBg: Color {
        Color.primary.opacity(0.01)
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
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header (Typing Bar)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 28, height: 28)
                    
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
                            placeholder: NSLocalizedString("New Space Name...", comment: "")
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
                                } else if viewModel.isBottomBarFocused {
                                    viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: false)
                                } else {
                                    viewModel.executeRowAction()
                                }
                            },
                            onCommandEnter: {
                                if viewModel.commandKTargetWindow != nil {
                                    viewModel.executeCommandKAction()
                                } else if viewModel.isBottomBarFocused {
                                    viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: true)
                                } else if viewModel.activeCommand?.type == .batchMoveWindows {
                                    viewModel.executeBatchMove()
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
                                } else if viewModel.activeCommand?.type == .batchMoveWindows && viewModel.stagingWindow == nil {
                                    viewModel.showCommandKPanel()
                                }
                            },
                            placeholder: viewModel.activeCommand == nil ? NSLocalizedString("Search commands...", comment: "") : (viewModel.stagingWindow != nil ? NSLocalizedString("Search target space...", comment: "") : NSLocalizedString("Search items...", comment: ""))
                        )
                        .frame(height: 36)
                    }
                    
                    if viewModel.isLoadingData {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    }
                }
                .frame(height: 52)
                .padding(.horizontal, 18)
                
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
            
            if let targetWindow = viewModel.commandKTargetWindow {
                CommandKOverlayView(viewModel: viewModel, window: targetWindow)
            }
        }
        .frame(width: 720, height: 450)
        .launcherBackground(cornerRadius: 16, borderColor: colors.border)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.20), radius: 24, x: 0, y: 12)
        .padding(60)
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
                            VStack(spacing: 4) {
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
                    }
                }
            } else {
                if viewModel.stagingWindow != nil {
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
                                        SpaceRowView(space: space, isSelected: isSelected, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && i < 9 ? "⌘\(i + 1)" : nil)
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
                                            SpaceRowView(space: space, isSelected: isSelected, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && i < 9 ? "⌘\(i + 1)" : nil)
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
                        let windows = viewModel.filteredWindows
                        if windows.isEmpty {
                            EmptyResultsView()
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(spacing: 4) {
                                        ForEach(0..<windows.count, id: \.self) { i in
                                            let window = windows[i]
                                            let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == i
                                            WindowRowView(window: window, isSelected: isSelected, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && i < 9 ? "⌘\(i + 1)" : nil)
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
                        
                    case .batchMoveWindows:
                        let sections = viewModel.batchMoveSections
                        if sections.isEmpty {
                            EmptyResultsView()
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(sections) { section in
                                            ListSectionHeader(title: section.title, subtitle: section.subtitle)
                                            
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
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(isSelected ? .white : colors.textSecondary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                isSelected
                    ? Color.white.opacity(0.20)
                    : colors.badgeBg
            )
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? Color.white.opacity(0.30) : colors.badgeBorder, lineWidth: 1)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.textPrimary)
                .frame(width: 28, height: 28)
                .background(colors.badgeBg)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(colors.badgeBorder, lineWidth: 1)
                )
            
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
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(statusText == "Enabled" ? colors.greenText : colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(statusText == "Enabled" ? colors.greenText.opacity(0.12) : colors.badgeBg)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(statusText == "Enabled" ? colors.greenText.opacity(0.3) : Color.clear, lineWidth: 1)
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
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
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
    var shortcutText: String? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.textPrimary)
                .frame(width: 28, height: 28)
                .background(colors.badgeBg)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(colors.badgeBorder, lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(space.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                
                Text(verbatim: String(format: String(localized: "%@ · Space %lld"), space.displayName, space.num))
                    .font(.subheadline)
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
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
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
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
                .frame(width: 20, height: 20)
                .padding(4)
                .frame(width: 28, height: 28)
                .background(colors.badgeBg)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(colors.badgeBorder, lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)

                Text(verbatim: String(format: String(localized: "%@ · %@"), window.ownerName, window.space.name))
                    .font(.subheadline)
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let shortcut = shortcutText {
                KeycapView(text: LocalizedStringKey(shortcut), isSelected: isSelected)
            } else {
                KeycapView(text: "Focus ↵", isSelected: isSelected)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
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
                .frame(width: 20, height: 20)
                .padding(4)
                .frame(width: 28, height: 28)
                .background(colors.badgeBg)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(colors.badgeBorder, lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)

                let stateLabel: String = {
                    var isMin = false
                    var isHid = false
                    if let app = NSRunningApplication(processIdentifier: window.pid) {
                        isHid = app.isHidden
                    }
                    if let axWindow = SpaceHelper.getAXWindow(id: window.id, pid: window.pid) {
                        var minimizedRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                           let isMinimized = minimizedRef as? Bool {
                            isMin = isMinimized
                        }
                    }
                    if isMin {
                        return NSLocalizedString("Minimized", comment: "")
                    } else if isHid {
                        return NSLocalizedString("Hidden", comment: "")
                    } else {
                        return NSLocalizedString("Active", comment: "")
                    }
                }()

                Text(verbatim: String(format: "%@ · %@ · %@", window.ownerName, window.space.name, stateLabel))
                    .font(.subheadline)
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let shortcut = shortcutText {
                KeycapView(text: LocalizedStringKey(shortcut), isSelected: isSelected)
            } else if isStaged {
                Text(stagedActionText)
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(colors.greenText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(colors.greenText.opacity(0.12))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(colors.greenText.opacity(0.3), lineWidth: 1)
                    )
            } else {
                Text(window.space.name)
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(colors.badgeBg)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(colors.badgeBorder, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
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
                .foregroundColor(colors.textQuaternary)
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
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
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color.accentColor)
                    Text(viewModel.activeCommand?.title ?? String(localized: "Batch Move Windows"))
                        .font(.caption)
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
                            .font(.caption.weight(.semibold))
                            .foregroundColor(colors.greenText)
                        Text(String(format: NSLocalizedString("Stage: %@", comment: ""), staging.ownerName))
                            .font(.caption)
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
                        Text(verbatim: String(localized: "Stage to Space"))
                        Text("↵")
                            .font(.system(.caption2, design: .monospaced))
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
                                        .font(.system(.caption2, design: .monospaced))
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
                                    Text(verbatim: String(localized: "Stage Move to Desktop..."))
                                    Text("↵")
                                        .font(.system(.caption2, design: .monospaced))
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
                                        .font(.system(.caption2, design: .monospaced))
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
                                .font(.system(.caption2, design: .monospaced))
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
            Text(verbatim: String(localized: "Spaces:"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(colors.textTertiary)
                .padding(.trailing, 2)
            
            let spaces = spaceManager.currentDisplaySpaces
            
            ForEach(0..<spaces.count, id: \.self) { i in
                let space = spaces[i]
                let isCurrent = space.id == spaceManager.currentSpaceUUID
                let isSpaceSelected = viewModel.isBottomBarFocused && i == viewModel.selectedSpaceIndex
                let name = spaceManager.getSpaceName(space.id)
                
                Button(action: {
                    let isOptionPressed = NSEvent.modifierFlags.contains(.option)
                    if isOptionPressed {
                        let handled = viewModel.movePreviouslyActiveWindow(toSpaceID: space.id)
                        if !handled {
                            viewModel.closeLauncher()
                        }
                    } else {
                        viewModel.executeSwitchToSpaceID(space.id)
                    }
                }) {
                    Text(name)
                        .modifier(BottomBarCapsule(isSelected: isSpaceSelected, isActive: isCurrent, colorScheme: colorScheme))
                }
                .buttonStyle(PlainButtonStyle())
                .focusable(false)
                .help(String(localized: "Click to switch, Option+Click to move active window."))
            }
            
            Spacer()
            
            // Right side action indicators
            HStack(spacing: 8) {
                if !viewModel.isBottomBarFocused {
                    Button(action: {
                        viewModel.isBottomBarFocused = true
                        viewModel.isKeyboardSelection = true
                        
                        let spaces = spaceManager.currentDisplaySpaces
                        if let currentSpaceID = AppDelegate.shared.spaceManager?.currentSpaceUUID,
                           let index = spaces.firstIndex(where: { $0.id == currentSpaceID }) {
                            viewModel.selectedSpaceIndex = index
                        } else {
                            viewModel.selectedSpaceIndex = 0
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(LocalizedStringKey("Switch Space"))
                            Text("Tab")
                                .font(.system(.caption2, design: .monospaced))
                                .fontWeight(.semibold)
                        }
                        .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if viewModel.isBottomBarFocused {
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey("Switch Space"))
                        Text("↵")
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.bold)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: false)
                    }
                    
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey("Move Window"))
                        Text("⌥↵")
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.bold)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.executeBottomBarSpaceAction(isOption: true, isCommand: false)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey("Action"))
                        Text("↵")
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.bold)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.executeRowAction()
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(colors.bottomBarBg)
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
                    Image(systemName: active.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color.accentColor)
                    Text(active.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(colors.textPrimary)
                }
                .modifier(BottomBarCapsule(isSelected: false, isActive: true, colorScheme: colorScheme))
            }
            
            Spacer()
            
            // Right side: Context-sensitive actions
            if let type = viewModel.activeCommand?.type {
                switch type {
                case .switchToDesktop:
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Switch Space"))
                        Text("↵")
                            .font(.system(.caption2, design: .monospaced))
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
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.bold)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.executeRowAction()
                    }

                case .listWindows:
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Focus Window"))
                        Text("↵")
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.bold)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.executeRowAction()
                    }

                case .renameCurrentSpace:
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Rename Space"))
                        Text("↵")
                            .font(.system(.caption2, design: .monospaced))
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
    var isTypingDisabled: Bool = false

    override var acceptsFirstResponder: Bool {
        return true
    }



    override func performKeyEquivalent(with event: NSEvent) -> Bool {
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
        textField.isTypingDisabled = isTypingDisabled
        
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = .labelColor
        textField.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        
        context.coordinator.lastPlaceholder = placeholder
        context.coordinator.lastIsDark = isDark
        
        let placeholderAttr = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: NSFont.systemFont(ofSize: 16, weight: .regular)
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
                    .font: NSFont.systemFont(ofSize: 16, weight: .regular)
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
            // Glassy background dimming
            Group {
                if #available(macOS 26.0, *) {
                    Group {
                        Color.black.opacity(colorScheme == .dark ? 0.35 : 0.15)
                    }
                    .glassEffect(.regular, in: Rectangle())
                } else {
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, state: .active)
                        .opacity(0.85)
                }
            }
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
                    let (minimized, hidden) = viewModel.isWindowMinimizedOrAppHidden(window)
                    if minimized {
                        Text(verbatim: String(localized: "Minimized"))
                            .font(.system(.caption2, design: .default))
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    } else if hidden {
                        Text(verbatim: String(localized: "Hidden"))
                            .font(.system(.caption2, design: .default))
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    } else {
                        Text(verbatim: String(localized: "Active"))
                            .font(.system(.caption2, design: .default))
                            .fontWeight(.bold)
                            .foregroundColor(colors.greenText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(colors.greenText.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
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
        case .fullscreen: return "arrow.up.left.and.arrow.down.right"
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
        case .fullscreen: return NSLocalizedString("Fullscreen", comment: "")
        case .quit: return NSLocalizedString("Quit", comment: "")
        case .restore: return NSLocalizedString("Restore", comment: "")
        case .restoreTo: return NSLocalizedString("Restore to...", comment: "")
        case .move(let space): return String(format: NSLocalizedString("Move to %@", comment: ""), space.name)
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
}

struct BottomBarCapsule: ViewModifier {
    let isSelected: Bool
    let isActive: Bool
    var isGreen: Bool = false
    let colorScheme: ColorScheme
    
    func body(content: Content) -> some View {
        content
            .font(.caption)
            .fontWeight(isSelected || isActive ? .semibold : .medium)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(
                ZStack {
                    if isSelected {
                        isGreen ? Color.green : Color.primary.opacity(0.08)
                    } else if isActive {
                        isGreen ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.15)
                    } else {
                        Color.primary.opacity(0.06)
                    }
                }
            )
            .foregroundColor(
                isActive ? (isGreen ? Color.green : Color.accentColor) : (isSelected ? .primary : .secondary)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.primary.opacity(0.15) : (isActive ? (isGreen ? Color.green.opacity(0.2) : Color.accentColor.opacity(0.2)) : Color.primary.opacity(0.08)),
                        lineWidth: 1
                    )
            )
            .shadow(color: isSelected ? (isGreen ? Color.green.opacity(0.25) : Color.primary.opacity(0.1)) : Color.clear, radius: 3, x: 0, y: 1)
    }
}

