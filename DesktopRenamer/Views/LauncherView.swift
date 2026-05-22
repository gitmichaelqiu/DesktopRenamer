import SwiftUI
import AppKit

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var spaceManager = AppDelegate.shared.spaceManager!
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, state: .active)
                .cornerRadius(12)
            Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.85)
                .cornerRadius(12)
            
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
                                .background(Color.white.opacity(0.08))
                                .foregroundColor(.white.opacity(0.8))
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            
                            if let staging = viewModel.stagingWindow {
                                Text("Stage: \(staging.ownerName)")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.08))
                                    .foregroundColor(.white.opacity(0.8))
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.3))
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
                
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                
                // Content area
                if viewModel.activeCommand?.type == .renameCurrentSpace {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "pencil.line")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(.white.opacity(0.4))
                        
                        Text("Rename Current Desktop Space")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("Type a new name above and press Enter to save")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
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
                
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                
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

struct KeycapView: View {
    let text: String
    let isSelected: Bool
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(isSelected ? 0.12 : 0.06))
            .cornerRadius(4)
    }
}

struct EmptyResultsView: View {
    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.white.opacity(0.2))
            Text("No results")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            Text("No commands or items matched your search query.")
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : Color(red: 0.0, green: 0.55, blue: 1.0))
                .frame(width: 28, height: 28)
                .background(isSelected ? Color(red: 0.0, green: 0.55, blue: 1.0) : Color.white.opacity(0.06))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.95))
                
                Text(command.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .white.opacity(0.45))
            }
            
            Spacer()
            
            if command.hasSubpage {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(isSelected ? 0.7 : 0.35))
                    .padding(.trailing, 4)
            } else {
                KeycapView(text: "Action", isSelected: isSelected)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
        .cornerRadius(6)
    }
}

struct SpaceRowView: View {
    let space: SpaceGroup
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : Color(red: 0.0, green: 0.55, blue: 1.0))
                .frame(width: 28, height: 28)
                .background(isSelected ? Color(red: 0.0, green: 0.55, blue: 1.0) : Color.white.opacity(0.06))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(space.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.95))
                
                Text("\(space.displayName) · Space \(space.num)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .white.opacity(0.45))
            }
            
            Spacer()
            
            KeycapView(text: "Switch ↵", isSelected: isSelected)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
        .cornerRadius(6)
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
                .frame(width: 20, height: 20)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? "(No Title)" : window.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.95))
                    .lineLimit(1)
                
                Text("\(window.ownerName) · \(window.space.name)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .white.opacity(0.45))
            }
            
            Spacer()
            
            KeycapView(text: "Focus ↵", isSelected: isSelected)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
        .cornerRadius(6)
    }
}

struct ConfirmBatchRowView: View {
    let count: Int
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.green.opacity(0.8))
                .cornerRadius(6)
            
            Text("Confirm & Execute Batch Move (\(count) window\(count == 1 ? "" : "s"))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : .green)
            
            Spacer()
            
            KeycapView(text: "Run ↵", isSelected: isSelected)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(isSelected ? 0.15 : 0.06))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.green.opacity(isSelected ? 0.3 : 0.1), lineWidth: 1)
        )
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
                .frame(width: 20, height: 20)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? "(No Title)" : window.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.95))
                    .lineLimit(1)
                
                Text("\(window.ownerName) · \(window.space.name)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .white.opacity(0.45))
            }
            
            Spacer()
            
            if isStaged {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Text("→ \(targetSpaceName)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(Color.green.opacity(0.12))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
            } else {
                KeycapView(text: "Stage ↵", isSelected: isSelected)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
        .cornerRadius(6)
    }
}

struct SpacesBottomBar: View {
    @ObservedObject var spaceManager: SpaceManager
    
    var body: some View {
        HStack(spacing: 8) {
            Text("Spaces:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
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
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    let isOptionPressed = NSEvent.modifierFlags.contains(.option)
                    if isOptionPressed {
                        spaceManager.moveActiveWindowToSpace(id: space.id)
                    } else {
                        spaceManager.switchToSpace(space, forceInstant: true)
                    }
                }
                .help("Click to switch, Option+Click to move active window.")
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.15))
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
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = .white
        textField.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        
        let placeholderAttr = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
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
        let placeholderAttr = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
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
