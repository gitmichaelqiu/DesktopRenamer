import SwiftUI
import AppKit

struct ThemeColors {
    let isDark: Bool
    
    var backgroundOverlay: Color {
        isDark ? Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.85) : Color(red: 0.95, green: 0.95, blue: 0.96).opacity(0.85)
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
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }
    
    var rowHover: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
    
    var badgeBg: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    
    var badgeBorder: Color {
        isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }
    
    var separator: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
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
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, state: .active)
            colors.backgroundOverlay
            
            VStack(spacing: 0) {
                // Header (Typing Bar)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                        .font(.system(size: 20, weight: .regular))
                    
                    if let active = viewModel.activeCommand {
                        HStack(spacing: 6) {
                            Text(active.title)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(colors.badgeBg)
                                .foregroundColor(colors.textSecondary)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(colors.badgeBorder, lineWidth: 1)
                                )
                            
                            if let staging = viewModel.stagingWindow {
                                Text("Stage: \(staging.ownerName)")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(colors.badgeBg)
                                    .foregroundColor(colors.textSecondary)
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(colors.badgeBorder, lineWidth: 1)
                                    )
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(colors.textQuaternary)
                        }
                    }
                    
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
                            placeholder: "New Space Name..."
                        )
                        .frame(height: 32)
                    } else {
                        SearchTextField(
                            text: $viewModel.searchQuery,
                            isDark: colors.isDark,
                            onUpArrow: {
                                if viewModel.selectedRowIndex > 0 {
                                    viewModel.selectedRowIndex -= 1
                                }
                            },
                            onDownArrow: {
                                if viewModel.selectedRowIndex < viewModel.visibleRowsCount - 1 {
                                    viewModel.selectedRowIndex += 1
                                }
                            },
                            onEnter: {
                                viewModel.executeRowAction()
                            },
                            onCommandEnter: {
                                if viewModel.activeCommand?.type == .batchMoveWindows {
                                    viewModel.executeBatchMove()
                                }
                            },
                            onEscape: {
                                viewModel.handleEscapeKey()
                            },
                            placeholder: viewModel.activeCommand == nil ? "Search commands..." : (viewModel.stagingWindow != nil ? "Search target space..." : "Search items...")
                        )
                        .frame(height: 32)
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
                        
                        Text("Rename Current Desktop Space")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.textPrimary)
                        
                        Text("Type a new name above and press Enter to save")
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
                        Text("Executing batch window moves...")
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
                if viewModel.activeCommand?.type == .batchMoveWindows {
                    BatchMoveBottomBar(viewModel: viewModel)
                } else {
                    SpacesBottomBar(viewModel: viewModel, spaceManager: spaceManager)
                }
            }
        }
        .frame(width: 580, height: 380)
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
                                    let isSelected = viewModel.selectedRowIndex == i
                                    CommandRowView(command: cmd, isSelected: isSelected)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            viewModel.selectedRowIndex = i
                                            viewModel.executeRowAction()
                                        }
                                        .id(i)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .onChange(of: viewModel.selectedRowIndex) { index in
                            withAnimation(.easeInOut(duration: 0.12)) {
                                proxy.scrollTo(index, anchor: .center)
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
                                        let isSelected = viewModel.selectedRowIndex == i
                                        SpaceRowView(space: space, isSelected: isSelected)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                viewModel.selectedRowIndex = i
                                                viewModel.executeRowAction()
                                            }
                                            .id(i)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .onChange(of: viewModel.selectedRowIndex) { index in
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    proxy.scrollTo(index, anchor: .center)
                                }
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
                                            let isSelected = viewModel.selectedRowIndex == i
                                            SpaceRowView(space: space, isSelected: isSelected)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    viewModel.selectedRowIndex = i
                                                    viewModel.executeRowAction()
                                                }
                                                .id(i)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                                .onChange(of: viewModel.selectedRowIndex) { index in
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        proxy.scrollTo(index, anchor: .center)
                                    }
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
                                            let isSelected = viewModel.selectedRowIndex == i
                                            WindowRowView(window: window, isSelected: isSelected)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    viewModel.selectedRowIndex = i
                                                    viewModel.executeRowAction()
                                                }
                                                .id(i)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                                .onChange(of: viewModel.selectedRowIndex) { index in
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        proxy.scrollTo(index, anchor: .center)
                                    }
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
                                                let isSelected = viewModel.selectedRowIndex == item.index
                                                
                                                switch item {
                                                case .staged(let move, _):
                                                    WindowBatchRowView(window: move.window, isSelected: isSelected, isStaged: true, targetSpaceName: move.targetSpace.name)
                                                        .contentShape(Rectangle())
                                                        .onTapGesture {
                                                            viewModel.selectedRowIndex = item.index
                                                            viewModel.executeRowAction()
                                                        }
                                                        .id(item.index)
                                                        
                                                case .unstaged(let window, _):
                                                    WindowBatchRowView(window: window, isSelected: isSelected, isStaged: false, targetSpaceName: "")
                                                        .contentShape(Rectangle())
                                                        .onTapGesture {
                                                            viewModel.selectedRowIndex = item.index
                                                            viewModel.executeRowAction()
                                                        }
                                                        .id(item.index)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                                .onChange(of: viewModel.selectedRowIndex) { index in
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        proxy.scrollTo(index, anchor: .center)
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
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isGreenRow && isSelected ? .white : (isSelected ? colors.textPrimary.opacity(0.9) : colors.textSecondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isGreenRow && isSelected ? Color.white.opacity(0.2) : colors.textPrimary.opacity(isSelected ? 0.12 : 0.06))
            .cornerRadius(4)
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
            Text("No results")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colors.textTertiary)
            Text("No commands or items matched your search query.")
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
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : Color(red: 0.0, green: 0.55, blue: 1.0))
                .frame(width: 28, height: 28)
                .background(isSelected ? Color(red: 0.0, green: 0.55, blue: 1.0) : colors.badgeBg)
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                
                Text(command.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
            }
            
            Spacer()
            
            if command.hasSubpage {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .padding(.trailing, 4)
            } else {
                KeycapView(text: "Action", isSelected: isSelected)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? colors.rowHover : Color.clear)
        .cornerRadius(6)
    }
}

struct SpaceRowView: View {
    let space: SpaceGroup
    let isSelected: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : Color(red: 0.0, green: 0.55, blue: 1.0))
                .frame(width: 28, height: 28)
                .background(isSelected ? Color(red: 0.0, green: 0.55, blue: 1.0) : colors.badgeBg)
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(space.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                
                Text("\(space.displayName) · Space \(space.num)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
            }
            
            Spacer()
            
            KeycapView(text: "Switch ↵", isSelected: isSelected)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? colors.rowHover : Color.clear)
        .cornerRadius(6)
    }
}

struct WindowRowView: View {
    let window: WindowEntry
    let isSelected: Bool
    @Environment(\.colorScheme) var colorScheme
    
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
                .frame(width: 28, height: 28)
                .background(colors.badgeBg)
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? "(No Title)" : window.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                
                Text("\(window.ownerName) · \(window.space.name)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
            }
            
            Spacer()
            
            KeycapView(text: "Focus ↵", isSelected: isSelected)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? colors.rowHover : Color.clear)
        .cornerRadius(6)
    }
}

struct ConfirmBatchRowView: View {
    let count: Int
    let isSelected: Bool
    @Environment(\.colorScheme) var colorScheme
    
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
            
            Text("Confirm & Execute Batch Move (\(count) window\(count == 1 ? "" : "s"))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : colors.greenText)
            
            Spacer()
            
            KeycapView(text: "Run ↵", isSelected: isSelected, isGreenRow: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? colors.greenText : colors.greenText.opacity(0.06))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(colors.greenText.opacity(isSelected ? 0.3 : 0.1), lineWidth: 1)
        )
    }
}

struct WindowBatchRowView: View {
    let window: WindowEntry
    let isSelected: Bool
    let isStaged: Bool
    let targetSpaceName: String
    @Environment(\.colorScheme) var colorScheme
    
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
                .frame(width: 28, height: 28)
                .background(colors.badgeBg)
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? "(No Title)" : window.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                
                Text("\(window.ownerName) · \(window.space.name)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
            }
            
            Spacer()
            
            if isStaged {
                HStack(spacing: 4) {
                    Circle()
                        .fill(colors.greenText)
                        .frame(width: 5, height: 5)
                    Text("→ \(targetSpaceName)")
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
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? colors.rowHover : Color.clear)
        .cornerRadius(6)
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
            // Left side: Active command pill matching Raycast look
            HStack(spacing: 6) {
                Image(systemName: viewModel.activeCommand?.iconName ?? "macwindow.badge.plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                Text(viewModel.activeCommand?.title ?? "Batch Move Windows")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(colors.badgeBg)
            .clipShape(Capsule())
            
            Spacer()
            
            // Right side: Context-sensitive actions
            HStack(spacing: 8) {
                if viewModel.stagingWindow != nil {
                    // Staging target space selection
                    HStack(spacing: 4) {
                        Text("Stage to Space")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                        Text("↵")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colors.textTertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(colors.badgeBg)
                    .cornerRadius(4)
                } else {
                    // Selecting an item in batch move
                    let items = viewModel.batchMoveSelectableItems
                    let index = viewModel.selectedRowIndex
                    
                    if index >= 0 && index < items.count {
                        let selectedItem = items[index]
                        switch selectedItem {
                        case .staged:
                            HStack(spacing: 4) {
                                Text("Unstage Move")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(colors.textSecondary)
                                Text("↵")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(colors.textQuaternary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(colors.badgeBg)
                            .cornerRadius(4)
                            
                        case .unstaged:
                            HStack(spacing: 4) {
                                Text("Stage Move to Desktop...")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(colors.textSecondary)
                                Text("↵")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(colors.textQuaternary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(colors.badgeBg)
                            .cornerRadius(4)
                        }
                    }
                    
                    // If there are staged moves, show run batch action
                    if !viewModel.stagedMoves.isEmpty {
                        HStack(spacing: 4) {
                            Text("Run Batch Move")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(colors.greenText)
                            Text("⌘↵")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(colors.greenText.opacity(0.8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(colors.greenText.opacity(0.1))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(colors.greenText.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                
                HStack(spacing: 4) {
                    Text("Actions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                    Text("⌘K")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colors.textQuaternary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(colors.badgeBg)
                .cornerRadius(4)
            }
        }
        .padding(.horizontal, 16)
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
            Text("Spaces:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(colors.textTertiary)
                .padding(.trailing, 2)
            
            let spaces = spaceManager.currentDisplaySpaces
            
            ForEach(spaces, id: \.id) { space in
                let isCurrent = space.id == spaceManager.currentSpaceUUID
                let name = spaceManager.getSpaceName(space.id)
                
                HStack {
                    if isCurrent {
                        Text(name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.0, green: 0.55, blue: 1.0))
                            .clipShape(Capsule())
                            .shadow(color: Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.4), radius: 4, x: 0, y: 0)
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
                .contentShape(Rectangle())
                .onTapGesture {
                    let isOptionPressed = NSEvent.modifierFlags.contains(.option)
                    if isOptionPressed {
                        let handled = viewModel.movePreviouslyActiveWindow(toSpaceID: space.id)
                        if !handled {
                            viewModel.closeLauncher()
                        }
                    } else {
                        viewModel.executeSwitchToSpaceID(space.id)
                    }
                }
                .help("Click to switch, Option+Click to move active window.")
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(colors.bottomBarBg)
    }
}

class FocusTextField: NSTextField {
    override var acceptsFirstResponder: Bool {
        return true
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
    var onEnter: () -> Void
    var onCommandEnter: (() -> Void)? = nil
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
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let isCommandPressed = NSEvent.modifierFlags.contains(.command)
                if isCommandPressed, let onCommandEnter = parent.onCommandEnter {
                    onCommandEnter()
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
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = isDark ? .white : NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        textField.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        
        let placeholderColor = isDark ? NSColor.white.withAlphaComponent(0.35) : NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.35)
        let placeholderAttr = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: NSFont.systemFont(ofSize: 18, weight: .regular)
            ]
        )
        textField.placeholderAttributedString = placeholderAttr
        
        textField.stringValue = text
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.textColor = isDark ? .white : NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        let placeholderColor = isDark ? NSColor.white.withAlphaComponent(0.35) : NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.35)
        let placeholderAttr = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: NSFont.systemFont(ofSize: 18, weight: .regular)
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
