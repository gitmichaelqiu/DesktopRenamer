import SwiftUI
import AppKit

struct ThemeColors {
    let isDark: Bool
    
    var backgroundOverlay: Color {
        isDark ? Color(red: 0.1, green: 0.1, blue: 0.11).opacity(0.65) : Color(red: 0.98, green: 0.98, blue: 0.99).opacity(0.65)
    }
    
    var textPrimary: Color {
        isDark ? .white : Color(red: 0.12, green: 0.12, blue: 0.14)
    }
    
    var textSecondary: Color {
        isDark ? .white.opacity(0.7) : Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.7)
    }
    
    var textTertiary: Color {
        isDark ? .white.opacity(0.45) : Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.45)
    }
    
    var textQuaternary: Color {
        isDark ? .white.opacity(0.3) : Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.3)
    }
    
    var border: Color {
        isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }
    
    var rowHover: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
    
    var badgeBg: Color {
        isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }
    
    var badgeBorder: Color {
        isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
    }
    
    var separator: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    
    var bottomBarBg: Color {
        isDark ? Color.black.opacity(0.15) : Color.black.opacity(0.05)
    }
    
    var greenText: Color {
        isDark ? Color.green : Color(red: 0.0, green: 0.5, blue: 0.15)
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
            VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)
            colors.backgroundOverlay
            
            VStack(spacing: 0) {
                // Header (Typing Bar)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(colors.textTertiary)
                        .font(.system(size: 20, weight: .regular))
                    
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
                        .frame(height: 44)
                    } else {
                        SearchTextField(
                            text: $viewModel.searchQuery,
                            isDark: colors.isDark,
                            onUpArrow: {
                                viewModel.isKeyboardSelection = true
                                if viewModel.selectedRowIndex > 0 {
                                    viewModel.selectedRowIndex -= 1
                                }
                            },
                            onDownArrow: {
                                viewModel.isKeyboardSelection = true
                                if viewModel.selectedRowIndex < viewModel.visibleRowsCount - 1 {
                                    viewModel.selectedRowIndex += 1
                                }
                            },
                            onLeftArrow: {
                                if viewModel.isBottomBarFocused {
                                    if viewModel.selectedSpaceIndex > 0 {
                                        viewModel.selectedSpaceIndex -= 1
                                    }
                                    return true
                                }
                                return false
                            },
                            onRightArrow: {
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
                                if viewModel.isBottomBarFocused {
                                    viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: false)
                                } else {
                                    viewModel.executeRowAction()
                                }
                            },
                            onCommandEnter: {
                                if viewModel.isBottomBarFocused {
                                    viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: true)
                                } else if viewModel.activeCommand?.type == .batchMoveWindows {
                                    viewModel.executeBatchMove()
                                }
                            },
                            onOptionEnter: {
                                if viewModel.isBottomBarFocused {
                                    viewModel.executeBottomBarSpaceAction(isOption: true, isCommand: false)
                                }
                            },
                            onCommandNumber: { num in
                                viewModel.executeNthRowAction(num - 1)
                            },
                            onTab: {
                                viewModel.handleTabKey()
                            },
                            onEscape: {
                                viewModel.handleEscapeKey()
                            },
                            placeholder: viewModel.activeCommand == nil ? NSLocalizedString("Search commands...", comment: "") : (viewModel.stagingWindow != nil ? NSLocalizedString("Search target space...", comment: "") : NSLocalizedString("Search items...", comment: ""))
                        )
                        .frame(height: 44)
                    }
                    
                    if viewModel.isLoadingData {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                
                Rectangle()
                    .fill(colors.separator)
                    .frame(height: 1)
                
                // Content area
                if viewModel.activeCommand?.type == .renameCurrentSpace {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "pencil.line")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(colors.textSecondary)
                        
                        Text(verbatim: String(localized: "Rename Current Space"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.textPrimary)

                        Text(verbatim: String(localized: "Type a new name above and press Enter to save"))
                            .font(.system(size: 11))
                            .foregroundColor(colors.textTertiary)
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
                } else if viewModel.isExecutingBatchMove {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(verbatim: String(localized: "Executing batch window moves..."))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
                } else {
                    ListAreaView(viewModel: viewModel)
                        .frame(maxHeight: .infinity)
                }
                
                Rectangle()
                    .fill(colors.separator)
                    .frame(height: 1)
                
                // Bottom bar
                if viewModel.activeCommand == nil {
                    SpacesBottomBar(viewModel: viewModel, spaceManager: spaceManager)
                } else if viewModel.activeCommand?.type == .batchMoveWindows {
                    BatchMoveBottomBar(viewModel: viewModel)
                } else {
                    CommandBottomBar(viewModel: viewModel)
                }
            }
        }
        .frame(width: 720, height: 450)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                                    CommandRowView(command: cmd, isSelected: isSelected, shortcutText: viewModel.showCommandNumbers && i < 9 ? "⌘\(i + 1)" : nil)
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
                                        SpaceRowView(space: space, isSelected: isSelected, shortcutText: viewModel.showCommandNumbers && i < 9 ? "⌘\(i + 1)" : nil)
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
                                            SpaceRowView(space: space, isSelected: isSelected, shortcutText: viewModel.showCommandNumbers && i < 9 ? "⌘\(i + 1)" : nil)
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
                                            WindowRowView(window: window, isSelected: isSelected, shortcutText: viewModel.showCommandNumbers && i < 9 ? "⌘\(i + 1)" : nil)
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
                                                    WindowBatchRowView(window: move.window, isSelected: isSelected, isStaged: true, targetSpaceName: move.targetSpace.name, shortcutText: viewModel.showCommandNumbers && item.index < 9 ? "⌘\(item.index + 1)" : nil)
                                                        .contentShape(Rectangle())
                                                        .onTapGesture {
                                                            viewModel.isKeyboardSelection = true
                                                            viewModel.selectedRowIndex = item.index
                                                            viewModel.executeRowAction()
                                                        }
                                                        .id(item.index)
                                                        
                                                case .unstaged(let window, _):
                                                    WindowBatchRowView(window: window, isSelected: isSelected, isStaged: false, targetSpaceName: "", shortcutText: viewModel.showCommandNumbers && item.index < 9 ? "⌘\(item.index + 1)" : nil)
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
    let text: String
    let isSelected: Bool
    var isGreenRow: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(isGreenRow && isSelected ? .white : (isSelected ? colors.textPrimary : colors.textSecondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                isGreenRow && isSelected ? Color.white.opacity(0.2) : colors.badgeBg
            )
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isGreenRow && isSelected ? Color.white.opacity(0.3) : colors.badgeBorder, lineWidth: 1)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colors.textTertiary)
            Text(verbatim: String(localized: "No commands matched your search query."))
                .font(.system(size: 11))
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
                .foregroundColor(isSelected ? .white : colors.textPrimary)
                .frame(width: 26, height: 26)
                .background(isSelected ? Color(red: 0.0, green: 0.55, blue: 1.0) : colors.badgeBg)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.clear : colors.badgeBorder, lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                
                Text(command.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let shortcut = shortcutText {
                KeycapView(text: shortcut, isSelected: isSelected)
            } else if let statusText = toggleStatus {
                Text(LocalizedStringKey(statusText))
                    .font(.system(size: 10, weight: .bold))
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .padding(.trailing, 4)
            } else {
                KeycapView(text: "Action", isSelected: isSelected)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? colors.rowHover : (isHovered ? colors.rowHover.opacity(0.5) : Color.clear))
        .cornerRadius(8)
        .onHover { hovering in
            isHovered = hovering
        }
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
                .foregroundColor(isSelected ? .white : colors.textPrimary)
                .frame(width: 26, height: 26)
                .background(isSelected ? Color(red: 0.0, green: 0.55, blue: 1.0) : colors.badgeBg)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.clear : colors.badgeBorder, lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(space.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                
                Text(verbatim: String(format: String(localized: "%@ · Space %lld"), space.displayName, space.num))
                    .font(.system(size: 11.5))
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let shortcut = shortcutText {
                KeycapView(text: shortcut, isSelected: isSelected)
            } else {
                KeycapView(text: "Switch ↵", isSelected: isSelected)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? colors.rowHover : (isHovered ? colors.rowHover.opacity(0.5) : Color.clear))
        .cornerRadius(8)
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
                .background(colors.badgeBg)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.clear : colors.badgeBorder, lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)

                Text(verbatim: String(format: String(localized: "%@ · %@"), window.ownerName, window.space.name))
                    .font(.system(size: 11.5))
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let shortcut = shortcutText {
                KeycapView(text: shortcut, isSelected: isSelected)
            } else {
                KeycapView(text: "Focus ↵", isSelected: isSelected)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? colors.rowHover : (isHovered ? colors.rowHover.opacity(0.5) : Color.clear))
        .cornerRadius(8)
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? colors.greenText : .white)
                .frame(width: 28, height: 28)
                .background(isSelected ? .white : colors.greenText.opacity(0.8))
                .cornerRadius(6)
            
            Text(verbatim: String(format: String(localized: "Confirm & Execute Batch Move (%lld window%@)"), count, count == 1 ? "" : "s"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : colors.greenText)
            
            Spacer()
            
            KeycapView(text: "Run ↵", isSelected: isSelected, isGreenRow: true)
        }
        .padding(.horizontal, 12)
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
    let targetSpaceName: String
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
                .background(colors.badgeBg)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.clear : colors.badgeBorder, lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)

                Text(verbatim: String(format: String(localized: "%@ · %@"), window.ownerName, window.space.name))
                    .font(.system(size: 11.5))
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let shortcut = shortcutText {
                KeycapView(text: shortcut, isSelected: isSelected)
            } else if isStaged {
                HStack(spacing: 4) {
                    Circle()
                        .fill(colors.greenText)
                        .frame(width: 5, height: 5)
                    Text(verbatim: String(format: String(localized: "→ %@"), targetSpaceName))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colors.greenText)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(colors.greenText.opacity(0.12))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(colors.greenText.opacity(0.3), lineWidth: 1)
                )
            } else {
                Text(window.space.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(colors.badgeBg)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(colors.badgeBorder, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? colors.rowHover : (isHovered ? colors.rowHover.opacity(0.5) : Color.clear))
        .cornerRadius(8)
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
        .padding(.horizontal, 12)
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                    Text(viewModel.activeCommand?.title ?? String(localized: "Batch Move Windows"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(colors.badgeBg)
                .clipShape(Capsule())
                
                if let staging = viewModel.stagingWindow {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(colors.textQuaternary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(colors.greenText)
                        Text(String(format: NSLocalizedString("Stage: %@", comment: ""), staging.ownerName))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(colors.badgeBg)
                    .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            // Right side: Context-sensitive actions
            HStack(spacing: 8) {
                if viewModel.stagingWindow != nil {
                    // Staging target space selection
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Stage to Space"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                        Text("↵")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colors.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(colors.badgeBg)
                    .clipShape(Capsule())
                } else {
                    // Selecting an item in batch move
                    let items = viewModel.batchMoveSelectableItems
                    let index = viewModel.selectedRowIndex
                    
                    if index >= 0 && index < items.count {
                        let selectedItem = items[index]
                        switch selectedItem {
                        case .staged:
                            HStack(spacing: 4) {
                                Text(verbatim: String(localized: "Unstage Move"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(colors.textSecondary)
                                Text("↵")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(colors.textQuaternary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(colors.badgeBg)
                            .clipShape(Capsule())
                            
                        case .unstaged:
                            HStack(spacing: 4) {
                                Text(verbatim: String(localized: "Stage Move to Desktop..."))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(colors.textSecondary)
                                Text("↵")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(colors.textQuaternary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(colors.badgeBg)
                            .clipShape(Capsule())
                        }
                    }
                    
                    // If there are staged moves, show run batch action
                    if !viewModel.stagedMoves.isEmpty {
                        HStack(spacing: 4) {
                            Text(verbatim: String(localized: "Run Batch Move"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(colors.greenText)
                            Text("⌘↵")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(colors.greenText.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(colors.greenText.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(colors.greenText.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
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
                .font(.system(size: 11, weight: .semibold))
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
                    HStack {
                        if isSpaceSelected {
                            Text(name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.0, green: 0.55, blue: 1.0))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                )
                                .shadow(color: Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.4), radius: 4, x: 0, y: 0)
                        } else if isCurrent {
                            Text(name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.15))
                                .clipShape(Capsule())
                        } else {
                            Text(name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(colors.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(colors.badgeBg)
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .focusable(false)
                .help(String(localized: "Click to switch, Option+Click to move active window."))
            }
            
            Spacer()
            
            // Right side action indicator
            HStack(spacing: 8) {
                if !viewModel.isBottomBarFocused {
                    Text(LocalizedStringKey("Use Tab to switch spaces quickly"))
                        .font(.system(size: 10.5))
                        .foregroundColor(colors.textTertiary)
                    
                    Text("•")
                        .font(.system(size: 10.5))
                        .foregroundColor(colors.textQuaternary)
                }
                
                HStack(spacing: 4) {
                    if viewModel.isBottomBarFocused {
                        Text(LocalizedStringKey("Switch / Move"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                        Text("↵ / ⌥↵")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colors.textQuaternary)
                    } else {
                        Text(LocalizedStringKey("Action"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                        Text("↵")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colors.textQuaternary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(colors.badgeBg)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                    Text(active.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(colors.badgeBg)
                .clipShape(Capsule())
            }
            
            Spacer()
            
            // Right side: Context-sensitive actions
            if let type = viewModel.activeCommand?.type {
                switch type {
                case .switchToDesktop:
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Switch Space"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                        Text("↵")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colors.textQuaternary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(colors.badgeBg)
                    .clipShape(Capsule())

                case .moveWindow:
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Move Window"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                        Text("↵")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colors.textQuaternary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(colors.badgeBg)
                    .clipShape(Capsule())

                case .listWindows:
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Focus Window"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                        Text("↵")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colors.textQuaternary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(colors.badgeBg)
                    .clipShape(Capsule())

                case .renameCurrentSpace:
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Rename Space"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                        Text("↵")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colors.textQuaternary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(colors.badgeBg)
                    .clipShape(Capsule())
                    
                default:
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(colors.bottomBarBg)
    }
}

class FocusTextField: NSTextField {
    var onCommandEnter: (() -> Void)?
    var onOptionEnter: (() -> Void)?
    var onCommandNumber: ((Int) -> Void)?

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

struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    var isDark: Bool
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
    var placeholder: String = "Type a command..."
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchTextField
        
        init(_ parent: SearchTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
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
        textField.onCommandEnter = {
            self.onCommandEnter?()
        }
        textField.onOptionEnter = {
            self.onOptionEnter?()
        }
        textField.onCommandNumber = { num in
            self.onCommandNumber?(num)
        }
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = isDark ? .white : NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        textField.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        
        let placeholderColor = isDark ? NSColor.white.withAlphaComponent(0.35) : NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.35)
        let placeholderAttr = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: NSFont.systemFont(ofSize: 20, weight: .regular)
            ]
        )
        textField.placeholderAttributedString = placeholderAttr
        
        textField.stringValue = text
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if let focusField = nsView as? FocusTextField {
            focusField.onCommandEnter = {
                self.onCommandEnter?()
            }
            focusField.onOptionEnter = {
                self.onOptionEnter?()
            }
            focusField.onCommandNumber = { num in
                self.onCommandNumber?(num)
            }
        }
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.textColor = isDark ? .white : NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        let placeholderColor = isDark ? NSColor.white.withAlphaComponent(0.35) : NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.35)
        let placeholderAttr = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: NSFont.systemFont(ofSize: 20, weight: .regular)
            ]
        )
        nsView.placeholderAttributedString = placeholderAttr
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
