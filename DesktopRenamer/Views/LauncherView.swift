import SwiftUI
import AppKit

enum LauncherLayout {
    static let windowSize = CGSize(width: 750, height: 475)
}

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

private struct LauncherActionBarModifier: ViewModifier {
    let colors: ThemeColors
    let height: CGFloat
    let horizontalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(colors.bottomBarBg)
    }
}

private extension View {
    func launcherActionBar(colors: ThemeColors, height: CGFloat = 46, horizontalPadding: CGFloat = 18) -> some View {
        modifier(LauncherActionBarModifier(colors: colors, height: height, horizontalPadding: horizontalPadding))
    }
}

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var spaceManager: SpaceManager
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header (Typing Bar)
                HStack(spacing: 6) {
                    Button(action: {
                        if viewModel.activeCommand != nil || viewModel.stagingWindow != nil {
                            viewModel.handleEscapeKey()
                        }
                    }) {
                        if viewModel.activeCommand == nil && viewModel.stagingWindow == nil {
                            LauncherMarkView(color: colors.textSecondary)
                        } else {
                            Image(systemName: "chevron.left")
                                .foregroundColor(colors.textSecondary)
                                .font(.system(size: 20, weight: .medium))
                                .frame(width: 28, height: 28)
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(viewModel.activeCommand == nil && viewModel.stagingWindow == nil ? 0.72 : 1)
                    
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
                            onBackspace: {
                                if viewModel.renameInputText.isEmpty {
                                    viewModel.handleEscapeKey()
                                }
                            },
                            onKeyEquivalent: { _ in false },
                            placeholder: NSLocalizedString("New Space Name...", comment: "")
                        )
                        .frame(height: 46)
                    } else {
                        SearchTextField(
                            text: $viewModel.searchQuery,
                            isDark: colors.isDark,
                            isTypingDisabled: viewModel.commandKTargetWindow != nil,
                            onUpArrow: {
                                if viewModel.isRootActionsPresented {
                                    viewModel.selectPreviousRootAction()
                                } else if viewModel.commandKTargetWindow != nil {
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
                                if viewModel.isRootActionsPresented {
                                    viewModel.selectNextRootAction()
                                } else if viewModel.commandKTargetWindow != nil {
                                    viewModel.selectNextCommandKAction()
                                } else if viewModel.stagingWindow != nil {
                                    let count = viewModel.filteredSpaces.count
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
                                if viewModel.isRootActionsPresented {
                                    viewModel.executeRootAction()
                                } else if viewModel.commandKTargetWindow != nil {
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
                                if viewModel.isRootActionsPresented {
                                    viewModel.executeRootAction()
                                } else if viewModel.commandKTargetWindow != nil {
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
                                } else if viewModel.activeCommand == nil {
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
                                if viewModel.isRootActionsPresented {
                                    let indices = viewModel.filteredRootActionIndices
                                    let index = num - 1
                                    if index >= 0 && index < indices.count {
                                        viewModel.selectedRootActionIndex = indices[index]
                                        viewModel.executeRootAction()
                                    }
                                } else if viewModel.commandKTargetWindow != nil {
                                    let actions = viewModel.filteredCommandKActions
                                    let index = num - 1
                                    if index >= 0 && index < actions.count {
                                        viewModel.commandKSelectedIndex = index
                                        viewModel.executeCommandKAction()
                                    }
                                } else if viewModel.stagingWindow != nil {
                                    let index = num - 1
                                    let count = viewModel.filteredSpaces.count
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
                            onBackspace: {
                                if viewModel.searchQuery.isEmpty {
                                    viewModel.handleEscapeKey()
                                }
                            },
                            onCommandK: {
                                if viewModel.commandKTargetWindow != nil {
                                    viewModel.commandKTargetWindow = nil
                                } else if viewModel.isRootActionsPresented {
                                    viewModel.isRootActionsPresented = false
                                } else if viewModel.activeCommand == nil {
                                    viewModel.showRootActionsPanel()
                                } else if (viewModel.activeCommand?.type == .batchMoveWindows || viewModel.activeCommand?.type == .listWindows) && viewModel.stagingWindow == nil {
                                    viewModel.showCommandKPanel()
                                }
                            },
                            onKeyEquivalent: { event in
                                return self.handleTextFieldKeyEquivalent(event)
                            },
                            placeholder: searchPlaceholder
                        )
                        .frame(height: 46)
                    }
                    
                    if viewModel.isLoadingData {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    }
                }
                .frame(height: 72)
                .padding(.horizontal, 16)
                
                if viewModel.activeCommand != nil {
                    Divider()
                }
                
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
                        .id(viewModel.activeCommand?.id ?? "root")
                        .transition(commandPageTransition)
                }
                
                if viewModel.activeCommand != nil {
                    Divider()
                }
                
                // Bottom bar
                ZStack(alignment: .bottom) {
                    if viewModel.activeCommand == nil {
                        RootLauncherBottomBar(viewModel: viewModel, spaceManager: spaceManager)
                            .transition(commandPageTransition)
                    } else if viewModel.activeCommand?.type == .batchMoveWindows {
                        BatchMoveBottomBar(viewModel: viewModel)
                            .transition(commandPageTransition)
                    } else {
                        CommandBottomBar(viewModel: viewModel)
                            .transition(commandPageTransition)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .animation(.easeInOut(duration: 0.18), value: viewModel.activeCommand?.id)
            
            switch viewModel.launcherOverlay {
            case .commandK(let targetWindow):
                CommandKOverlayView(viewModel: viewModel, window: targetWindow)
            case .rootActions:
                RootActionsOverlay(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            case .rootSpacePicker, .stagingSpacePicker:
                SpacePickerOverlay(viewModel: viewModel, spaceManager: spaceManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            case nil:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: viewModel.launcherOverlay)
        .onChange(of: spaceManager.currentSpaceUUID) { _ in
            viewModel.selectCurrentTargetSpace()
        }
        .onChange(of: viewModel.launcherOverlay) { overlay in
            guard overlay == nil else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("FocusLauncherTextField"), object: nil)
            }
        }
        .frame(width: LauncherLayout.windowSize.width, height: LauncherLayout.windowSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .opaqueLauncherBackground(cornerRadius: 24, isDark: colors.isDark, borderColor: colors.border)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.20), radius: 24, x: 0, y: 12)
    }

    private var searchPlaceholder: String {
        guard let commandType = viewModel.activeCommand?.type else {
            return NSLocalizedString("Search for apps and commands...", comment: "")
        }

        switch commandType {
        case .listWindows:
            return NSLocalizedString("Search windows...", comment: "")
        case .switchToDesktop, .moveWindow:
            return NSLocalizedString("Search target space...", comment: "")
        default:
            return viewModel.stagingWindow == nil
                ? NSLocalizedString("Search items...", comment: "")
                : NSLocalizedString("Search windows...", comment: "")
        }
    }

    private var commandPageTransition: AnyTransition {
        if viewModel.activeCommand == nil {
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }

        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

private struct LauncherMarkView: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let half = min(size.width, size.height) * 0.32
            var diamond = Path()
            diamond.move(to: CGPoint(x: center.x, y: center.y - half))
            diamond.addLine(to: CGPoint(x: center.x + half, y: center.y))
            diamond.addLine(to: CGPoint(x: center.x, y: center.y + half))
            diamond.addLine(to: CGPoint(x: center.x - half, y: center.y))
            diamond.closeSubpath()
            context.stroke(diamond, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineJoin: .miter))

            var stripes = Path()
            for offset in stride(from: -half * 0.55, through: half * 0.55, by: half * 0.36) {
                stripes.move(to: CGPoint(x: center.x - half * 0.62, y: center.y + offset + half * 0.62))
                stripes.addLine(to: CGPoint(x: center.x + half * 0.62, y: center.y + offset - half * 0.62))
            }
            context.stroke(stripes, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .square))
        }
        .frame(width: 28, height: 28)
    }
}

struct ListAreaView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var selectionNamespace
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.activeCommand == nil {
                // Main command list
                let sections = viewModel.rootCommandSections
                let commands = sections.flatMap(\.commands)
                if commands.isEmpty {
                    EmptyResultsView()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(sections) { section in
                                    if let title = section.title {
                                        Text(verbatim: title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(colors.textSecondary)
                                            .padding(.horizontal, 8)
                                            .padding(.top, section.startIndex == 0 ? 4 : 10)
                                            .padding(.bottom, 2)
                                    }
                                    ForEach(Array(section.commands.enumerated()), id: \.element.id) { localIndex, cmd in
                                        let index = section.startIndex + localIndex
                                        let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == index
                                        Button {
                                            viewModel.isKeyboardSelection = true
                                            viewModel.selectedRowIndex = index
                                            viewModel.executeRowAction()
                                        } label: {
                                            CommandRowView(command: cmd, isSelected: isSelected, isRoot: true, isCompact: true, selectionNamespace: selectionNamespace, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && index < 9 ? "⌘\(index + 1)" : nil)
                                        }
                                        .buttonStyle(.plain)
                                        .onHover { hovering in
                                            if hovering {
                                                viewModel.selectPointerRow(index)
                                            }
                                        }
                                        .id(cmd.id)
                                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .animation(.easeInOut(duration: 0.14), value: commands.map(\.id))
                        }
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
                switch viewModel.activeCommand?.type {
                    case .switchToDesktop, .moveWindow:
                        let spaces = viewModel.filteredSpaces
                        if spaces.isEmpty {
                            EmptyResultsView()
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(spacing: 4) {
                                        ForEach(Array(spaces.enumerated()), id: \.element.id) { i, space in
                                            let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == i
                                            let shortcut = viewModel.activeCommand?.type == .moveWindow ? "⌥⌘\(i + 1)" : "⌘\(i + 1)"
                                            Button {
                                                    viewModel.isKeyboardSelection = true
                                                    viewModel.selectedRowIndex = i
                                                    viewModel.executeRowAction()
                                            } label: {
                                                SpaceRowView(space: space, isSelected: isSelected, isCurrent: AppDelegate.shared.spaceManager?.currentSpaceUUID == space.id, selectionNamespace: selectionNamespace, shortcutText: i < 9 ? shortcut : nil)
                                            }
                                            .buttonStyle(.plain)
                                            .onHover { hovering in
                                                if hovering {
                                                    viewModel.selectPointerRow(i)
                                                }
                                            }
                                            .id(space.id)
                                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .animation(.easeInOut(duration: 0.14), value: spaces.map(\.id))
                                }
                                .onChange(of: viewModel.selectedRowIndex) { index in
                                    if viewModel.isKeyboardSelection {
                                        withAnimation(.easeInOut(duration: 0.12)) {
                                            guard spaces.indices.contains(index) else { return }
                                            proxy.scrollTo(spaces[index].id, anchor: .center)
                                        }
                                    }
                                }
                                .onAppear {
                                    guard spaces.indices.contains(viewModel.selectedRowIndex) else { return }
                                    proxy.scrollTo(spaces[viewModel.selectedRowIndex].id, anchor: .center)
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
                                        ForEach(Array(sections.enumerated()), id: \.element.id) { sIdx, section in
                                            ListSectionHeader(title: section.title, subtitle: section.subtitle, isFirst: sIdx == 0)
                                            
                                            ForEach(section.items) { item in
                                                let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == item.index
                                                Button {
                                                    viewModel.isKeyboardSelection = true
                                                    viewModel.selectedRowIndex = item.index
                                                    viewModel.executeRowAction()
                                                } label: {
                                                    WindowRowView(
                                                        window: item.window,
                                                        isSelected: isSelected,
                                                        selectionNamespace: selectionNamespace,
                                                        shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && item.index < 9 ? "⌘\(item.index + 1)" : nil
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                                .onHover { hovering in
                                                    if hovering {
                                                        viewModel.selectPointerRow(item.index)
                                                    }
                                                }
                                                .id(item.id)
                                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .animation(.easeInOut(duration: 0.14), value: sections.flatMap { $0.items }.map { $0.id })
                                }
                                .onChange(of: viewModel.selectedRowIndex) { index in
                                    if viewModel.isKeyboardSelection {
                                        withAnimation(.easeInOut(duration: 0.12)) {
                                            if let item = sections.flatMap({ $0.items }).first(where: { $0.index == index }) {
                                                proxy.scrollTo(item.id, anchor: .center)
                                            }
                                        }
                                    }
                                }
                                .onAppear {
                                    if let item = sections.flatMap({ $0.items }).first(where: { $0.index == viewModel.selectedRowIndex }) {
                                        proxy.scrollTo(item.id, anchor: .center)
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
                                        ForEach(Array(sections.enumerated()), id: \.element.id) { sIdx, section in
                                            ListSectionHeader(title: section.title, subtitle: section.subtitle, isFirst: sIdx == 0)
                                            
                                            ForEach(section.items) { item in
                                                let isSelected = !viewModel.isBottomBarFocused && viewModel.selectedRowIndex == item.index
                                                
                                                switch item {
                                                case .staged(let move, _):
                                                    Button {
                                                            viewModel.isKeyboardSelection = true
                                                            viewModel.selectedRowIndex = item.index
                                                            viewModel.executeRowAction()
                                                    } label: {
                                                        WindowBatchRowView(window: move.window, isSelected: isSelected, isStaged: true, stagedActionText: move.actionType.description, selectionNamespace: selectionNamespace, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && item.index < 9 ? "⌘\(item.index + 1)" : nil)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .onHover { hovering in
                                                        if hovering {
                                                            viewModel.selectPointerRow(item.index)
                                                        }
                                                    }
                                                    .id(item.id)
                                                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                                        
                                                case .unstaged(let window, _):
                                                    Button {
                                                            viewModel.isKeyboardSelection = true
                                                            viewModel.selectedRowIndex = item.index
                                                            viewModel.executeRowAction()
                                                    } label: {
                                                        WindowBatchRowView(window: window, isSelected: isSelected, isStaged: false, stagedActionText: "", selectionNamespace: selectionNamespace, shortcutText: viewModel.showCommandNumbers && viewModel.commandKTargetWindow == nil && item.index < 9 ? "⌘\(item.index + 1)" : nil)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .onHover { hovering in
                                                        if hovering {
                                                            viewModel.selectPointerRow(item.index)
                                                        }
                                                    }
                                                    .id(item.id)
                                                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .animation(.easeInOut(duration: 0.14), value: sections.flatMap { $0.items }.map { $0.id })
                                }
                                .onChange(of: viewModel.selectedRowIndex) { index in
                                    if viewModel.isKeyboardSelection {
                                        withAnimation(.easeInOut(duration: 0.12)) {
                                            if let item = sections.flatMap({ $0.items }).first(where: { $0.index == index }) {
                                                proxy.scrollTo(item.id, anchor: .center)
                                            }
                                        }
                                    }
                                }
                                .onAppear {
                                    DispatchQueue.main.async {
                                        if let item = sections.flatMap({ $0.items }).first(where: { $0.index == viewModel.selectedRowIndex }) {
                                            proxy.scrollTo(item.id, anchor: .center)
                                        }
                                    }
                                }
                            }
                        }
                        
                default:
                    EmptyResultsView()
                }
            }
        }
        .onAppear {
            guard viewModel.activeCommand?.type == .switchToDesktop || viewModel.activeCommand?.type == .moveWindow else { return }
            // SpaceManager can finish reconciling the current UUID after the target list appears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                viewModel.selectCurrentTargetSpace()
            }
        }
        .onChange(of: viewModel.currentSpaces) { _ in
            viewModel.selectCurrentTargetSpace()
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

private struct LauncherRowSurface: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool
    let colors: ThemeColors
    let verticalPadding: CGFloat
    let selectionNamespace: Namespace.ID?

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, verticalPadding)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.16))
                        .modifier(SelectionSurfaceModifier(namespace: selectionNamespace))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isHovered ? colors.rowHover : .clear)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.primary.opacity(0.10) : .clear, lineWidth: 1)
            }
            .animation(.spring(response: 0.20, dampingFraction: 0.86), value: isSelected)
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct SelectionSurfaceModifier: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "launcher-selected-row", in: namespace)
        } else {
            content
        }
    }
}

private extension View {
    func launcherRowSurface(isSelected: Bool, isHovered: Bool, colors: ThemeColors, verticalPadding: CGFloat = 8, selectionNamespace: Namespace.ID? = nil) -> some View {
        modifier(LauncherRowSurface(isSelected: isSelected, isHovered: isHovered, colors: colors, verticalPadding: verticalPadding, selectionNamespace: selectionNamespace))
    }
}

struct CommandRowView: View {
    let command: LauncherCommand
    let isSelected: Bool
    var isRoot: Bool = false
    var isCompact: Bool = false
    var selectionNamespace: Namespace.ID? = nil
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
        Group {
            if isRoot {
                rootRow
            } else {
                detailRow
            }
        }
        .launcherRowSurface(isSelected: isSelected, isHovered: isHovered, colors: colors, verticalPadding: isCompact ? 6 : 8, selectionNamespace: selectionNamespace)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rootRow: some View {
        HStack(spacing: 8) {
            commandIcon

            Text(command.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
                .layoutPriority(2)

            Text(command.subtitle)
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 4)

            if let shortcut = shortcutText {
                KeycapView(text: LocalStringKey_compat(shortcut), isSelected: isSelected)
            }

            if let statusText = toggleStatus {
                statusBadge(statusText)
            } else {
                Text(verbatim: String(localized: "Command"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? colors.textPrimary : colors.textSecondary)
            }
        }
    }

    private var detailRow: some View {
        HStack(spacing: 8) {
            commandIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                
                Text(command.subtitle)
                    .font(.system(size: 14))
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
    }

    private var commandIcon: some View {
        Image(systemName: command.iconName)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(colors.textPrimary)
            .frame(width: 24, height: 24)
            .background(colors.badgeBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusBadge(_ statusText: String) -> some View {
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
    var selectionNamespace: Namespace.ID? = nil
    var shortcutText: String? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if space.isFullscreen, let appPath = space.appPath {
                let appIcon = NSWorkspace.shared.icon(forFile: appPath)
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                    .frame(width: 24, height: 24)
                    .background(colors.badgeBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(space.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                
                if space.isFullscreen {
                    Text(verbatim: String(format: String(localized: "%@ · Fullscreen"), space.displayName))
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(verbatim: String(format: String(localized: "%@ · Space %lld"), space.displayName, space.num))
                        .font(.system(size: 13))
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
            }
        }
        .launcherRowSurface(isSelected: isSelected, isHovered: isHovered, colors: colors, selectionNamespace: selectionNamespace)
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
    var selectionNamespace: Namespace.ID? = nil
    var shortcutText: String? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            let appIcon = NSWorkspace.shared.icon(forFile: window.appPath)
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)

                Text(window.ownerName)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? colors.textSecondary : colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
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
        .launcherRowSurface(isSelected: isSelected, isHovered: isHovered, colors: colors, selectionNamespace: selectionNamespace)
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
        HStack(spacing: 8) {
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
    var selectionNamespace: Namespace.ID? = nil
    var shortcutText: String? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            let appIcon = NSWorkspace.shared.icon(forFile: window.appPath)
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
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
                        .modifier(SelectionSurfaceModifier(namespace: selectionNamespace))
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(colors.textSecondary)
            
            Text(subtitle)
                .font(.system(size: 15))
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
                    Button {
                        viewModel.executeRowAction()
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: String(localized: "Stage"))
                            Text("↵")
                                .font(.system(.caption2))
                                .fontWeight(.bold)
                        }
                        .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    }
                    .buttonStyle(.plain)
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

                            Button {
                                viewModel.executeRowAction()
                            } label: {
                                HStack(spacing: 4) {
                                    Text(verbatim: String(localized: isMove ? "Unstage Move" : "Unstage Action"))
                                    Text("↵")
                                        .font(.system(.subheadline))
                                        .fontWeight(.bold)
                                }
                                .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                            }
                            .buttonStyle(.plain)

                        case .unstaged:
                            Button {
                                viewModel.executeRowAction()
                            } label: {
                                HStack(spacing: 4) {
                                    Text(verbatim: String(localized: "Move to..."))
                                    Text("↵")
                                        .font(.system(.subheadline))
                                        .fontWeight(.bold)
                                }
                                .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                            }
                            .buttonStyle(.plain)

                            Button {
                                viewModel.showCommandKPanel()
                            } label: {
                                HStack(spacing: 4) {
                                    Text(verbatim: String(localized: "Actions"))
                                    Text("⌘K")
                                        .font(.system(.subheadline))
                                        .fontWeight(.bold)
                                }
                                .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // If there are staged moves, show run batch action
                    if !viewModel.stagedMoves.isEmpty {
                        Button {
                            viewModel.executeBatchMove()
                        } label: {
                            HStack(spacing: 4) {
                                Text(verbatim: String(localized: "Run Batch Actions"))
                                Text("⌘↵")
                                    .font(.system(.subheadline))
                                    .fontWeight(.bold)
                            }
                            .modifier(BottomBarCapsule(isSelected: true, isActive: false, isGreen: true, colorScheme: colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .launcherActionBar(colors: colors)
    }
}

struct RootLauncherBottomBar: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var spaceManager: SpaceManager
    @Environment(\.colorScheme) var colorScheme

    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.commandKTargetWindow = nil
                viewModel.currentSpaces = spaceManager.currentDisplaySpaces.map { space in
                    SpaceGroup(
                        id: space.id,
                        name: spaceManager.getSpaceName(space.id),
                        displayName: space.displayID,
                        num: space.num,
                        isFullscreen: space.isFullscreen,
                        appPath: space.appPath
                    )
                }
                if let currentIndex = spaceManager.currentDisplaySpaces.firstIndex(where: { $0.id == spaceManager.currentSpaceUUID }) {
                    viewModel.selectedSpaceIndex = currentIndex
                }
                viewModel.isRootActionsPresented = false
                viewModel.spacePickerQuery = ""
                viewModel.isRootSpacePickerPresented = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.10), in: Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Switch Space"))
            .help(String(localized: "Switch Space"))

            Spacer()

            HStack(spacing: 4) {
                Button {
                    viewModel.executeRowAction()
                } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: String(localized: "Open Command"))
                        KeycapView(text: "↵", isSelected: false, verticalPadding: 4, horizontalPadding: 4)
                    }
                    .foregroundColor(colors.textPrimary)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.showRootActionsPanel()
                } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: String(localized: "Actions"))
                        KeycapView(text: "⌘K", isSelected: false, verticalPadding: 4, horizontalPadding: 4)
                    }
                    .foregroundColor(viewModel.isRootActionsPresented ? colors.textPrimary : colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(colors.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.primary.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.28), lineWidth: 1))
        }
        .launcherActionBar(colors: colors, horizontalPadding: 8)
    }
}

struct RootActionsOverlay: View {
    @ObservedObject var viewModel: LauncherViewModel
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var actionSelectionNamespace

    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    private var selectedCommandTitle: String {
        guard viewModel.filteredCommands.indices.contains(viewModel.selectedRowIndex) else {
            return String(localized: "Actions")
        }
        return viewModel.filteredCommands[viewModel.selectedRowIndex].title
    }

    private var selectedCommand: LauncherCommand? {
        guard viewModel.filteredCommands.indices.contains(viewModel.selectedRowIndex) else {
            return nil
        }
        return viewModel.filteredCommands[viewModel.selectedRowIndex]
    }

    private var actionRows: [(index: Int, title: String, icon: String, shortcut: String)] {
        let isSelectedFavorite = viewModel.filteredCommands.indices.contains(viewModel.selectedRowIndex) && viewModel.isFavorite(viewModel.filteredCommands[viewModel.selectedRowIndex])
        let favoriteTitle = isSelectedFavorite
            ? String(localized: "Remove from Favorites")
            : String(localized: "Add to Favorites")
        var actions = [
            (index: 0, title: String(localized: "Open Command"), icon: "rectangle.and.pencil.and.ellipsis", shortcut: "↵"),
            (index: 1, title: favoriteTitle, icon: "star", shortcut: "⌘F"),
        ]
        if isSelectedFavorite {
            actions.append(contentsOf: [
                (index: 2, title: String(localized: "Move Favorite Up"), icon: "arrow.up", shortcut: "⌘↑"),
                (index: 3, title: String(localized: "Move Favorite Down"), icon: "arrow.down", shortcut: "⌘↓")
            ])
        }
        actions.append(
            (index: 4, title: String(localized: "Reset Ranking"), icon: "arrow.counterclockwise", shortcut: "↻")
        )
        let indices = Set(viewModel.filteredRootActionIndices)
        return actions.filter { indices.contains($0.index) }
    }

    private var groupedActionRows: [(title: String, rows: [(index: Int, title: String, icon: String, shortcut: String)])] {
        let rows = actionRows
        return [
            (String(localized: "Primary Action"), rows.filter { $0.index == 0 }),
            (String(localized: "Favorites"), rows.filter { (1...3).contains($0.index) }),
            (String(localized: "Manage"), rows.filter { $0.index == 4 })
        ].filter { !$0.rows.isEmpty }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button {
                viewModel.isRootActionsPresented = false
            } label: {
                Color.clear
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: selectedCommand?.iconName ?? "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                        .frame(width: 26, height: 26)
                        .background(colors.badgeBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: selectedCommandTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(colors.textPrimary)
                            .lineLimit(1)

                        Text(verbatim: selectedCommand?.subtitle ?? String(localized: "Command"))
                            .font(.caption)
                            .foregroundColor(colors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

                VStack(spacing: 2) {
                    if actionRows.isEmpty {
                        Text(verbatim: String(localized: "No actions found"))
                            .font(.subheadline)
                            .foregroundColor(colors.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else if viewModel.rootActionQuery.isEmpty {
                        ForEach(groupedActionRows, id: \.title) { section in
                            Text(verbatim: section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(colors.textTertiary)
                                .padding(.horizontal, 12)
                                .padding(.top, section.title == String(localized: "Primary Action") ? 0 : 8)
                                .padding(.bottom, 2)

                            ForEach(section.rows, id: \.index) { row in
                                rootActionRow(row: row, selectionNamespace: actionSelectionNamespace)
                            }
                        }
                    } else {
                        ForEach(actionRows, id: \.index) { row in
                            rootActionRow(row: row, selectionNamespace: actionSelectionNamespace)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

                Divider()

                SearchTextField(
                    text: $viewModel.rootActionQuery,
                    isDark: colors.isDark,
                    onUpArrow: {
                        viewModel.selectPreviousRootAction()
                    },
                    onDownArrow: {
                        viewModel.selectNextRootAction()
                    },
                    onCommandUpArrow: {
                        viewModel.moveFavoriteSelectedCommand(direction: -1)
                    },
                    onCommandDownArrow: {
                        viewModel.moveFavoriteSelectedCommand(direction: 1)
                    },
                    onEnter: {
                        viewModel.executeRootAction()
                    },
                    onEscape: {
                        viewModel.handleEscapeKey()
                    },
                    onBackspace: {
                        if viewModel.rootActionQuery.isEmpty {
                            viewModel.handleEscapeKey()
                        }
                    },
                    onCommandK: {
                        viewModel.isRootActionsPresented = false
                    },
                    onKeyEquivalent: { event in
                        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                        guard event.type == .keyDown,
                              modifiers.contains(.command),
                              !modifiers.contains(.shift),
                              !modifiers.contains(.option),
                              !modifiers.contains(.control),
                              event.charactersIgnoringModifiers?.lowercased() == "f",
                              viewModel.filteredRootActionIndices.contains(1) else {
                            return false
                        }
                        viewModel.selectedRootActionIndex = 1
                        viewModel.executeRootAction()
                        return true
                    },
                    placeholder: String(localized: "Search for actions..."),
                    focusNotificationName: NSNotification.Name("FocusRootActionTextField")
                )
                .frame(height: 44)
            }
            .frame(width: 350)
            .spacePickerSurface(colors: colors)
            .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
            .padding(.trailing, 16)
            .padding(.bottom, 8)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: NSNotification.Name("FocusRootActionTextField"), object: nil)
            }
        }
    }

    private func rootActionRow(row: (index: Int, title: String, icon: String, shortcut: String), selectionNamespace: Namespace.ID) -> some View {
        Button {
            viewModel.selectedRootActionIndex = row.index
            viewModel.executeRootAction()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: row.icon)
                    .font(.body.weight(.medium))
                    .frame(width: 18)
                    .foregroundColor(colors.textSecondary)

                Text(verbatim: row.title)
                    .font(.body.weight(viewModel.selectedRootActionIndex == row.index ? .semibold : .regular))
                Spacer()
                KeycapView(text: LocalizedStringKey(row.shortcut), isSelected: viewModel.selectedRootActionIndex == row.index, verticalPadding: 3, horizontalPadding: 5)
            }
            .foregroundColor(colors.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background {
                if viewModel.selectedRootActionIndex == row.index {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.16))
                        .modifier(SelectionSurfaceModifier(namespace: selectionNamespace))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.clear)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                viewModel.selectedRootActionIndex = row.index
            }
        }
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
        HStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let spaces = spaceManager.currentDisplaySpaces
                        ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                            let isCurrent = space.id == spaceManager.currentSpaceUUID
                            let isSelected = viewModel.isBottomBarFocused && index == viewModel.selectedSpaceIndex

                            Button(action: {
                                if NSEvent.modifierFlags.contains(.option) {
                                    let handled = viewModel.movePreviouslyActiveWindow(toSpaceID: space.id)
                                    if !handled {
                                        viewModel.closeLauncher()
                                    }
                                } else {
                                    viewModel.executeSwitchToSpaceID(space.id)
                                }
                            }) {
                                Text(spaceManager.getSpaceName(space.id))
                                    .modifier(BottomBarCapsule(isSelected: isSelected, isActive: isCurrent, colorScheme: colorScheme))
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .help(String(localized: "Click to switch, Option+Click to move active window."))
                            .id(space.id)
                        }
                    }
                    .padding(.leading, 32)
                    .padding(.trailing, 32)
                }
                .mask(
                    HStack(spacing: 0) {
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 32)

                        Rectangle()
                            .fill(Color.black)

                        LinearGradient(
                            gradient: Gradient(colors: [.black, .clear]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 32)
                    }
                )
                .onAppear {
                    scrollProxy.scrollTo(spaceManager.currentSpaceUUID, anchor: UnitPoint(x: 0.31, y: 0.5))
                }
                .onChange(of: spaceManager.currentSpaceUUID) { currentSpaceID in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollProxy.scrollTo(currentSpaceID, anchor: UnitPoint(x: 0.31, y: 0.5))
                    }
                }
                .onChange(of: viewModel.selectedSpaceIndex) { selectedIndex in
                    if viewModel.isBottomBarFocused {
                        let spaces = spaceManager.currentDisplaySpaces
                        if selectedIndex >= 0 && selectedIndex < spaces.count {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                scrollProxy.scrollTo(spaces[selectedIndex].id, anchor: UnitPoint(x: 0.31, y: 0.5))
                            }
                        }
                    }
                }
                .onChange(of: viewModel.isBottomBarFocused) { isFocused in
                    if isFocused {
                        let spaces = spaceManager.currentDisplaySpaces
                        if viewModel.selectedSpaceIndex >= 0 && viewModel.selectedSpaceIndex < spaces.count {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                scrollProxy.scrollTo(spaces[viewModel.selectedSpaceIndex].id, anchor: UnitPoint(x: 0.31, y: 0.5))
                            }
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            scrollProxy.scrollTo(spaceManager.currentSpaceUUID, anchor: UnitPoint(x: 0.31, y: 0.5))
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Rectangle()
                    .fill(colors.border)
                    .frame(width: 1, height: 16)

                HStack(spacing: 8) {
                    if viewModel.isBottomBarFocused {
                        bottomBarAction(title: "Switch Space", shortcut: "↵") {
                            viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: false)
                        }
                        bottomBarAction(title: "Move Window", shortcut: "⌥↵") {
                            viewModel.executeBottomBarSpaceAction(isOption: true, isCommand: false)
                        }
                    }

                    if !viewModel.isBottomBarFocused {
                        bottomBarAction(title: "Action", shortcut: "↵") {
                            viewModel.executeRowAction()
                        }
                    }
                }
            }
            .padding(.leading, 12)
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(colors.bottomBarBg)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isBottomBarFocused)
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
    @Namespace private var selectionNamespace

    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button {
                viewModel.handleEscapeKey()
            } label: {
                Color.clear
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: viewModel.stagingWindow == nil
                     ? String(localized: "Switch Space")
                     : String(localized: "Stage Move to Desktop..."))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(colors.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 4) {
                        let spaces = viewModel.filteredSpaces
                        if spaces.isEmpty {
                            Text(verbatim: String(localized: "No spaces found"))
                                .font(.subheadline)
                                .foregroundColor(colors.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                                let isSelected = index == viewModel.selectedSpaceIndex
                                Button(action: {
                                    viewModel.selectedSpaceIndex = index
                                    if viewModel.stagingWindow != nil {
                                        viewModel.selectedRowIndex = index
                                        viewModel.executeRowAction()
                                    } else {
                                        viewModel.executeSelectedSpacePickerAction()
                                    }
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "desktopcomputer")
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
                                    .background {
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(Color.primary.opacity(0.16))
                                                .modifier(SelectionSurfaceModifier(namespace: selectionNamespace))
                                        } else {
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(Color.clear)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    if hovering {
                                        viewModel.selectedSpaceIndex = index
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                    .animation(.easeInOut(duration: 0.14), value: viewModel.filteredSpaces.map { $0.id })
                    .animation(.easeOut(duration: 0.12), value: viewModel.selectedSpaceIndex)
                }
                .frame(maxHeight: 220)

                if viewModel.stagingWindow != nil {
                    Divider()

                    SearchTextField(
                        text: $viewModel.spacePickerQuery,
                        isDark: colors.isDark,
                        onUpArrow: {
                            viewModel.selectedSpaceIndex = max(0, viewModel.selectedSpaceIndex - 1)
                        },
                        onDownArrow: {
                            let count = viewModel.filteredSpaces.count
                            if viewModel.selectedSpaceIndex < count - 1 {
                                viewModel.selectedSpaceIndex += 1
                            }
                        },
                        onEnter: {
                            viewModel.executeSelectedSpacePickerAction()
                        },
                        onCommandNumber: { number in
                            let index = number - 1
                            guard index >= 0 && index < viewModel.filteredSpaces.count else { return }
                            viewModel.selectedSpaceIndex = index
                            viewModel.executeSelectedSpacePickerAction()
                        },
                        onEscape: {
                            viewModel.handleEscapeKey()
                        },
                        onBackspace: {
                            if viewModel.spacePickerQuery.isEmpty {
                                viewModel.handleEscapeKey()
                            }
                        },
                        onKeyEquivalent: { _ in false },
                        placeholder: String(localized: "Search..."),
                        focusNotificationName: NSNotification.Name("FocusSpacePickerTextField")
                    )
                        .frame(height: 44)
                }
            }
            .frame(width: viewModel.stagingWindow == nil ? 290 : 350)
            .spacePickerSurface(colors: colors)
            .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
            .padding(.trailing, 16)
            .padding(.bottom, 8)
        }
        .onAppear {
            guard viewModel.stagingWindow != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: NSNotification.Name("FocusSpacePickerTextField"), object: nil)
            }
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
                    actionButton(title: "Switch", shortcut: "↵") {
                        viewModel.executeRowAction()
                    }

                case .moveWindow:
                    actionButton(title: "Move", shortcut: "↵") {
                        viewModel.executeRowAction()
                    }

                case .listWindows:
                    if viewModel.stagingWindow != nil {
                        actionButton(title: "Move", shortcut: "↵") {
                            viewModel.executeRowAction()
                        }
                    } else {
                        HStack(spacing: 8) {
                            actionButton(title: "Focus", shortcut: "↵") {
                                viewModel.executeRowAction()
                            }
                            
                            actionButton(title: "Move", shortcut: "⌘M") {
                                if let window = viewModel.selectedWindowForListWindows {
                                    viewModel.batchMoveLastSelectedIndex = viewModel.selectedRowIndex
                                    viewModel.stagingWindow = window
                                    viewModel.isExecutingRestoreToImmediately = true
                                    viewModel.selectedRowIndex = 0
                                }
                            }
                            
                            actionButton(title: "Actions", shortcut: "⌘K") {
                                viewModel.showCommandKPanel()
                            }
                        }
                    }

                case .renameCurrentSpace:
                    actionButton(title: "Rename Space", shortcut: "↵") {
                        viewModel.executeRowAction()
                    }
                    
                default:
                    EmptyView()
                }
            }
        }
        .launcherActionBar(colors: colors)
    }

    private func actionButton(title: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(verbatim: String(localized: String.LocalizationValue(title)))
                Text(shortcut)
                    .font(.system(.subheadline))
                    .fontWeight(.bold)
            }
            .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
        }
        .buttonStyle(.plain)
    }
}

class FocusTextField: NSTextField {
    var focusNotificationName = NSNotification.Name("FocusLauncherTextField")
    var onCommandEnter: (() -> Void)?
    var onOptionEnter: (() -> Void)?
    var onCommandNumber: ((Int) -> Void)?
    var onCommandK: (() -> Void)?
    var onBackspace: (() -> Void)?
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
            NotificationCenter.default.addObserver(self, selector: #selector(forceFocus), name: focusNotificationName, object: nil)
            if window?.isKeyWindow == true {
                DispatchQueue.main.async { [weak self] in
                    self?.forceFocus()
                }
            }
        } else {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: focusNotificationName, object: nil)
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
    var onCommandUpArrow: (() -> Void)? = nil
    var onCommandDownArrow: (() -> Void)? = nil
    var onLeftArrow: (() -> Bool)? = nil
    var onRightArrow: (() -> Bool)? = nil
    var onEnter: () -> Void
    var onCommandEnter: (() -> Void)? = nil
    var onOptionEnter: (() -> Void)? = nil
    var onCommandNumber: ((Int) -> Void)? = nil
    var onTab: (() -> Void)? = nil
    var onEscape: () -> Void
    var onBackspace: (() -> Void)? = nil
    var onCommandK: (() -> Void)? = nil
    var onKeyEquivalent: ((NSEvent) -> Bool)? = nil
    var placeholder: String = "Type a command..."
    var focusNotificationName = NSNotification.Name("FocusLauncherTextField")
    
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
                if NSEvent.modifierFlags.contains(.command), let onCommandUpArrow = parent.onCommandUpArrow {
                    onCommandUpArrow()
                    return true
                }
                parent.onUpArrow()
                return true
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if NSEvent.modifierFlags.contains(.command), let onCommandDownArrow = parent.onCommandDownArrow {
                    onCommandDownArrow()
                    return true
                }
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
            } else if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                if parent.text.isEmpty, let onBackspace = parent.onBackspace {
                    onBackspace()
                    return true
                }
            }
            return false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = FocusTextField()
        textField.focusNotificationName = focusNotificationName
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
        textField.onBackspace = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onBackspace?()
        }
        textField.onKeyEquivalent = onKeyEquivalent
        textField.isTypingDisabled = isTypingDisabled
        
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = .labelColor
        textField.font = NSFont.systemFont(ofSize: 22, weight: .regular)
        
        context.coordinator.lastPlaceholder = placeholder
        context.coordinator.lastIsDark = isDark
        
        let placeholderAttr = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: NSFont.systemFont(ofSize: 22, weight: .regular)
            ]
        )
        textField.placeholderAttributedString = placeholderAttr
        
        textField.stringValue = text
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        
        if let focusField = nsView as? FocusTextField {
            focusField.focusNotificationName = focusNotificationName
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
                    .font: NSFont.systemFont(ofSize: 22, weight: .regular)
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
    @Namespace private var actionSelectionNamespace
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button {
                viewModel.commandKTargetWindow = nil
            } label: {
                Color.clear
            }
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                Text(window.ownerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                ScrollView {
                    let actions = viewModel.filteredCommandKActions.map(CommandKActionItem.init)
                    VStack(spacing: 2) {
                        if actions.isEmpty {
                            Text(verbatim: String(localized: "No actions found"))
                                .font(.subheadline)
                                .foregroundColor(colors.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        } else {
                            ForEach(Array(actions.enumerated()), id: \.element.id) { idx, item in
                                CommandKActionRowView(
                                    action: item.action,
                                    isSelected: viewModel.commandKSelectedIndex == idx,
                                    showCommandNumbers: viewModel.showCommandNumbers,
                                    idx: idx,
                                    colors: colors,
                                    viewModel: viewModel,
                                    selectionNamespace: actionSelectionNamespace
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 230)

                Divider()

                SearchTextField(
                    text: $viewModel.commandKQuery,
                    isDark: colors.isDark,
                    onUpArrow: {
                        viewModel.selectPreviousCommandKAction()
                    },
                    onDownArrow: {
                        viewModel.selectNextCommandKAction()
                    },
                    onEnter: {
                        viewModel.executeCommandKAction()
                    },
                    onCommandNumber: { number in
                        let index = number - 1
                        guard index >= 0 && index < viewModel.filteredCommandKActions.count else { return }
                        viewModel.commandKSelectedIndex = index
                        viewModel.executeCommandKAction()
                    },
                    onEscape: {
                        viewModel.commandKTargetWindow = nil
                    },
                    onBackspace: {
                        if viewModel.commandKQuery.isEmpty {
                            viewModel.commandKTargetWindow = nil
                        }
                    },
                    onCommandK: {
                        viewModel.commandKTargetWindow = nil
                    },
                    onKeyEquivalent: { _ in false },
                    placeholder: String(localized: "Search for actions..."),
                    focusNotificationName: NSNotification.Name("FocusCommandKTextField")
                )
                .frame(height: 44)
            }
            .frame(width: 350)
            .spacePickerSurface(colors: colors)
            .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
            .padding(.trailing, 16)
            .padding(.bottom, 8)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: NSNotification.Name("FocusCommandKTextField"), object: nil)
            }
        }
    }
}

private struct CommandKActionItem: Identifiable {
    let action: BatchStagedActionType

    var id: String {
        action.description
    }
}

struct CommandKActionRowView: View {
    let action: BatchStagedActionType
    let isSelected: Bool
    let showCommandNumbers: Bool
    let idx: Int
    let colors: ThemeColors
    @ObservedObject var viewModel: LauncherViewModel
    let selectionNamespace: Namespace.ID?
    
    @State private var isHovered = false
    
    var body: some View {
        Button {
            viewModel.commandKSelectedIndex = idx
            viewModel.executeCommandKAction()
        } label: {
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
                            .modifier(SelectionSurfaceModifier(namespace: selectionNamespace))
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }
                }
            )
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

private struct LauncherGlassSurface: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        makeSurfaceView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.wantsLayer = true
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.masksToBounds = true

        if #available(macOS 26.0, *), let glassView = nsView as? NSGlassEffectView {
            glassView.contentView = nil
        } else if let effectView = nsView as? NSVisualEffectView {
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.state = .active
        }
    }

    private func makeSurfaceView() -> NSView {
        let surface: NSView
        if #available(macOS 26.0, *) {
            surface = NSGlassEffectView(frame: .zero)
        } else {
            let effectView = NSVisualEffectView(frame: .zero)
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            surface = effectView
        }

        surface.wantsLayer = true
        surface.layer?.cornerRadius = cornerRadius
        surface.layer?.masksToBounds = true
        return surface
    }
}

extension View {
    func opaqueLauncherBackground(cornerRadius: CGFloat, isDark: Bool, borderColor: Color) -> some View {
        background(
            isDark
                ? Color(red: 0.22, green: 0.225, blue: 0.24)
                : Color(nsColor: .windowBackgroundColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor.opacity(isDark ? 0.5 : 0.8), lineWidth: 1)
        )
    }

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
        self
            .background(LauncherGlassSurface(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(colors.border.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
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
            .frame(height: 30)
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

        if event.keyCode == 53 && hasCommand && !hasShift && !hasOption && !hasControl {
            viewModel.popToRoot()
            return true
        }

        if viewModel.activeCommand == nil,
           viewModel.commandKTargetWindow == nil,
           !viewModel.isRootActionsPresented,
           hasCommand && !hasShift && !hasOption && !hasControl,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            viewModel.toggleFavoriteSelectedCommand()
            return true
        }
        
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
