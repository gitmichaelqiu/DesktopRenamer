import SwiftUI
import AppKit

struct LauncherView: View {
    @StateObject var viewModel = LauncherViewModel()
    @ObservedObject var spaceManager = AppDelegate.shared.spaceManager!
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, state: .active)
                .cornerRadius(12)
            
            VStack(spacing: 0) {
                // Header (Typing Bar)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.blue)
                        .font(.system(size: 18, weight: .semibold))
                    
                    if let active = viewModel.activeCommand {
                        HStack(spacing: 6) {
                            Text(active.title)
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                            
                            if let staging = viewModel.stagingWindow {
                                Text("→ Stage: \(staging.ownerName)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .cornerRadius(6)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    if viewModel.activeCommand?.type == .renameCurrentSpace {
                        SearchTextField(
                            text: $viewModel.renameInputText,
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
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Content area
                if viewModel.activeCommand?.type == .renameCurrentSpace {
                    VStack(spacing: 16) {
                        Image(systemName: "pencil.and.outline")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                            .padding(.top, 40)
                        
                        Text("Rename Current Desktop Space")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("Type a new name above and press Enter to save")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Spacer()
                    }
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                } else if viewModel.isExecutingBatchMove {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Executing batch window moves...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                } else {
                    ListAreaView(viewModel: viewModel)
                        .frame(height: 260)
                }
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                // Spaces bottom bar
                SpacesBottomBar(spaceManager: spaceManager)
            }
        }
        .frame(width: 580, height: 380)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

struct ListAreaView: View {
    @ObservedObject var viewModel: LauncherViewModel
    
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
                        let windows = viewModel.filteredWindows
                        let hasStaged = !viewModel.stagedMoves.isEmpty
                        let totalRows = (hasStaged ? 1 : 0) + windows.count
                        
                        if totalRows == 0 {
                            EmptyResultsView()
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(spacing: 4) {
                                        ForEach(0..<totalRows, id: \.self) { i in
                                            let isSelected = viewModel.selectedRowIndex == i
                                            
                                            if hasStaged && i == 0 {
                                                // Confirm Batch Action Row
                                                ConfirmBatchRowView(count: viewModel.stagedMoves.count, isSelected: isSelected)
                                                    .contentShape(Rectangle())
                                                    .onTapGesture {
                                                        viewModel.selectedRowIndex = i
                                                        viewModel.executeRowAction()
                                                    }
                                                    .id(i)
                                            } else {
                                                let wIndex = hasStaged ? i - 1 : i
                                                let window = windows[wIndex]
                                                let isStaged = viewModel.stagedMoves[window.id] != nil
                                                let targetName = viewModel.stagedMoves[window.id]?.targetSpace.name ?? ""
                                                
                                                WindowBatchRowView(window: window, isSelected: isSelected, isStaged: isStaged, targetSpaceName: targetName)
                                                    .contentShape(Rectangle())
                                                    .onTapGesture {
                                                        viewModel.selectedRowIndex = i
                                                        viewModel.executeRowAction()
                                                    }
                                                    .id(i)
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

struct EmptyResultsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            Text("No matching commands found")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            Text("Try searching for something else")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CommandRowView: View {
    let command: LauncherCommand
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .blue)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.blue.opacity(0.8) : Color.blue.opacity(0.15))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(command.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            if command.hasSubpage {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.trailing, 4)
            } else {
                Text("Action")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(isSelected ? 0.2 : 0.08))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
        .cornerRadius(8)
        .scaleEffect(isSelected ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

struct SpaceRowView: View {
    let space: SpaceGroup
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .purple)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.purple.opacity(0.8) : Color.purple.opacity(0.15))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(space.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("\(space.displayName) · Space \(space.num)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Text("Switch")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(isSelected ? 0.2 : 0.08))
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
        .cornerRadius(8)
        .scaleEffect(isSelected ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

struct WindowRowView: View {
    let window: WindowEntry
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            let appIcon = NSWorkspace.shared.icon(forFile: window.appPath)
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .cornerRadius(5)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? "(No Title)" : window.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(window.ownerName) · \(window.space.name)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Text("Focus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(isSelected ? 0.2 : 0.08))
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
        .cornerRadius(8)
        .scaleEffect(isSelected ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

struct ConfirmBatchRowView: View {
    let count: Int
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.green.opacity(0.8))
                .cornerRadius(8)
            
            Text("Confirm & Execute Batch Move (\(count) window\(count == 1 ? "" : "s"))")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(.green)
            
            Spacer()
            
            Text("Run")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.8))
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.green.opacity(0.2) : Color.green.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        .scaleEffect(isSelected ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

struct WindowBatchRowView: View {
    let window: WindowEntry
    let isSelected: Bool
    let isStaged: Bool
    let targetSpaceName: String
    
    var body: some View {
        HStack(spacing: 12) {
            let appIcon = NSWorkspace.shared.icon(forFile: window.appPath)
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .cornerRadius(5)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? "(No Title)" : window.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(window.ownerName) · \(window.space.name)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            if isStaged {
                Text("→ \(targetSpaceName)")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.25))
                    .foregroundColor(.green)
                    .cornerRadius(6)
            } else {
                Text("Stage")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(isSelected ? 0.2 : 0.08))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
        .cornerRadius(8)
        .scaleEffect(isSelected ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

struct SpacesBottomBar: View {
    @ObservedObject var spaceManager: SpaceManager
    
    var body: some View {
        HStack(spacing: 8) {
            Text("Spaces:")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .padding(.trailing, 4)
            
            let spaces = spaceManager.currentDisplaySpaces
            
            ForEach(spaces, id: \.id) { space in
                let isCurrent = space.id == spaceManager.currentSpaceUUID
                let name = spaceManager.getSpaceName(space.id)
                
                Text(name)
                    .font(.system(size: 11, weight: isCurrent ? .bold : .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        isCurrent
                        ? LinearGradient(colors: [Color.blue, Color.blue.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                    )
                    .foregroundColor(isCurrent ? .white : .white.opacity(0.8))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isCurrent ? Color.blue.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: isCurrent ? Color.blue.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
                    .help("Click to switch, Option+Click to move active window.")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let isOptionPressed = NSEvent.modifierFlags.contains(.option)
                        if isOptionPressed {
                            spaceManager.moveActiveWindowToSpace(id: space.id)
                        } else {
                            spaceManager.switchToSpace(space, forceInstant: true)
                        }
                    }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.35))
    }
}

class FocusTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: window)
            if window?.isKeyWindow == true {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.window?.makeFirstResponder(self)
                }
            }
        }
    }
    
    @objc private func windowDidBecomeKey() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void
    var onEnter: () -> Void
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
                parent.onEnter()
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
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = .white
        textField.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        textField.stringValue = text
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
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
