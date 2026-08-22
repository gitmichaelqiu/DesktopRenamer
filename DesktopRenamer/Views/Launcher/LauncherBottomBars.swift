import SwiftUI
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

    private let labelWidth: CGFloat = 56
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if viewModel.isBottomBarFocused {
                ZStack(alignment: .leading) {
                    Text(verbatim: String(localized: "Spaces:"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(colors.textTertiary)
                        .opacity(viewModel.spaceBarQuery.isEmpty ? 1 : 0)

                    SearchTextField(
                        text: $viewModel.spaceBarQuery,
                        isDark: colors.isDark,
                        onUpArrow: {},
                        onDownArrow: {},
                        onLeftArrow: {
                            viewModel.moveSpaceSelection(by: -1)
                            return true
                        },
                        onRightArrow: {
                            viewModel.moveSpaceSelection(by: 1)
                            return true
                        },
                        onEnter: {
                            viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: false)
                        },
                        onCommandEnter: {
                            viewModel.executeBottomBarSpaceAction(isOption: false, isCommand: true)
                        },
                        onOptionEnter: {
                            viewModel.executeBottomBarSpaceAction(isOption: true, isCommand: false)
                        },
                        onTab: {
                            viewModel.handleTabKey()
                        },
                        onEscape: {
                            viewModel.handleEscapeKey()
                        },
                        onKeyEquivalent: { _ in false },
                        placeholder: String(localized: "Spaces:"),
                        textFieldFont: NSFont.systemFont(ofSize: 13, weight: .semibold),
                        textFieldColor: NSColor.secondaryLabelColor.withAlphaComponent(0.65),
                        placeholderColor: NSColor.clear,
                        usesSingleLineMode: true,
                        textFieldLineBreakMode: .byTruncatingHead,
                        focusNotificationName: NSNotification.Name("FocusSpaceBarTextField")
                    )
                    .opacity(viewModel.spaceBarQuery.isEmpty ? 0.001 : 1)
                }
                .frame(width: labelWidth, height: 28, alignment: .leading)
                .padding(.trailing, 8)
            } else {
                Text(verbatim: String(localized: "Spaces:"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(colors.textTertiary)
                    .frame(width: labelWidth, alignment: .leading)
                    .padding(.trailing, 8)
                    .layoutPriority(1)
            }
            
            // Scrollable spaces list
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let spaces = viewModel.filteredDisplaySpaces
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
                            .id(space.id)
                        }
                    }
                    .padding(.leading, 32)
                    .padding(.trailing, 32)
                }
                .mask(
                    HStack(spacing: 0) {
                        // Left fade edge
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 32)
                        
                        // Middle opaque region
                        Rectangle()
                            .fill(Color.black)
                        
                        // Right fade edge
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
                        let spaces = viewModel.filteredDisplaySpaces
                        if selectedIndex >= 0 && selectedIndex < spaces.count {
                            let spaceID = spaces[selectedIndex].id
                            withAnimation(.easeInOut(duration: 0.15)) {
                                scrollProxy.scrollTo(spaceID, anchor: UnitPoint(x: 0.31, y: 0.5))
                            }
                        }
                    }
                }
                .onChange(of: viewModel.isBottomBarFocused) { isFocused in
                    let spaces = viewModel.filteredDisplaySpaces
                    if isFocused {
                        if viewModel.selectedSpaceIndex >= 0 && viewModel.selectedSpaceIndex < spaces.count {
                            let spaceID = spaces[viewModel.selectedSpaceIndex].id
                            withAnimation(.easeInOut(duration: 0.15)) {
                                scrollProxy.scrollTo(spaceID, anchor: UnitPoint(x: 0.31, y: 0.5))
                            }
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            scrollProxy.scrollTo(spaceManager.currentSpaceUUID, anchor: UnitPoint(x: 0.31, y: 0.5))
                        }
                    }
                }
            }
            
            // Actions Overlay (No longer overlapping, placed in-line)
            HStack(spacing: 12) {
                // Separator divider
                Rectangle()
                    .fill(colors.border)
                    .frame(width: 1, height: 16)
                
                // Right side action indicators
                HStack(spacing: 8) {
                    if !viewModel.isBottomBarFocused {
                        Button(action: {
                            viewModel.focusSpaceBar()
                        }) {
                            HStack(spacing: 4) {
                                Text(LocalizedStringKey("Switch Space"))
                                Text("⇥")
                                    .font(.system(.subheadline))
                                    .fontWeight(.bold)
                            }
                            .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if viewModel.isBottomBarFocused {
                        HStack(spacing: 4) {
                            Text(LocalizedStringKey("Switch Space"))
                            Text("↵")
                                .font(.system(.subheadline))
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
                                .font(.system(.subheadline))
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
                                .font(.system(.subheadline))
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
            .padding(.leading, 12)
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(colors.bottomBarBg)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isBottomBarFocused)
    }
}
