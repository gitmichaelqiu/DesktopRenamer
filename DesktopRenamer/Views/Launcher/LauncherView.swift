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
                            onKeyEquivalent: { _ in false },
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
                                if viewModel.commandKTargetWindow != nil {
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
            .blur(radius: viewModel.commandKTargetWindow != nil ? 10 : 0)
            .animation(.easeInOut(duration: 0.12), value: viewModel.commandKTargetWindow != nil)
            
            if let targetWindow = viewModel.commandKTargetWindow {
                CommandKOverlayView(viewModel: viewModel, window: targetWindow)
            }
        }
        .frame(width: 720, height: 450)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active
    @Environment(\.colorScheme) private var colorScheme
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        update(view)
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        update(nsView)
    }

    private func update(_ view: NSVisualEffectView) {
        let isDark = colorScheme == .dark
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
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
