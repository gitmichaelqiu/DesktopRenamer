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
                        .foregroundColor(.gray)
                        .font(.system(size: 20))
                    
                    if let active = viewModel.activeCommand {
                        HStack(spacing: 6) {
                            Text(active.title)
                                .font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                            
                            if let staging = viewModel.stagingWindow {
                                Text("→ Stage: \(staging.ownerName)")
                                    .font(.system(size: 13, weight: .semibold))
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
                        TextField("New Space Name...", text: $viewModel.renameInputText, onCommit: {
                            viewModel.executeRowAction()
                        })
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white)
                        .focusable(true)
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
                    VStack(spacing: 12) {
                        Text("Rename current desktop space")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Button("Confirm Rename (Enter)") {
                            viewModel.executeRowAction()
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                } else if viewModel.isExecutingBatchMove {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Executing batch window moves...")
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 240)
                } else {
                    ListAreaView(viewModel: viewModel)
                        .frame(height: 260)
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Spaces bottom bar
                SpacesBottomBar(spaceManager: spaceManager)
            }
        }
        .frame(width: 580, height: 380)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
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
                        List(0..<commands.count, id: \.self) { i in
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
                        .listStyle(.sidebar)
                        .onChange(of: viewModel.selectedRowIndex) { index in
                            proxy.scrollTo(index, anchor: .center)
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
                            List(0..<spaces.count, id: \.self) { i in
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
                            .listStyle(.sidebar)
                            .onChange(of: viewModel.selectedRowIndex) { index in
                                proxy.scrollTo(index, anchor: .center)
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
                                List(0..<spaces.count, id: \.self) { i in
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
                                .listStyle(.sidebar)
                                .onChange(of: viewModel.selectedRowIndex) { index in
                                    proxy.scrollTo(index, anchor: .center)
                                }
                            }
                        }
                        
                    case .listWindows:
                        let windows = viewModel.filteredWindows
                        if windows.isEmpty {
                            EmptyResultsView()
                        } else {
                            ScrollViewReader { proxy in
                                List(0..<windows.count, id: \.self) { i in
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
                                .listStyle(.sidebar)
                                .onChange(of: viewModel.selectedRowIndex) { index in
                                    proxy.scrollTo(index, anchor: .center)
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
                                List(0..<totalRows, id: \.self) { i in
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
                                .listStyle(.sidebar)
                                .onChange(of: viewModel.selectedRowIndex) { index in
                                    proxy.scrollTo(index, anchor: .center)
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
        VStack {
            Spacer()
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
            Text("No results found")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
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
                .font(.system(size: 16))
                .frame(width: 24, height: 24)
                .background(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text(command.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if command.hasSubpage {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.blue.opacity(0.25) : Color.clear)
        .cornerRadius(8)
    }
}

struct SpaceRowView: View {
    let space: SpaceGroup
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 16))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(space.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text("\(space.displayName) · Space \(space.num)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.blue.opacity(0.25) : Color.clear)
        .cornerRadius(8)
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
                .frame(width: 24, height: 24)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? "(No Title)" : window.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(window.ownerName) · \(window.space.name)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.blue.opacity(0.25) : Color.clear)
        .cornerRadius(8)
    }
}

struct ConfirmBatchRowView: View {
    let count: Int
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
                .frame(width: 24, height: 24)
            
            Text("Confirm & Execute Batch Move (\(count) window\(count == 1 ? "" : "s"))")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.green)
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.green.opacity(0.2) : Color.clear)
        .cornerRadius(8)
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
                .frame(width: 24, height: 24)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? "(No Title)" : window.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(window.ownerName) · \(window.space.name)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isStaged {
                Text("→ \(targetSpaceName)")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.blue.opacity(0.25) : Color.clear)
        .cornerRadius(8)
    }
}

struct SpacesBottomBar: View {
    @ObservedObject var spaceManager: SpaceManager
    
    var body: some View {
        HStack(spacing: 8) {
            Text("Spaces:")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.trailing, 4)
            
            let spaces = spaceManager.currentDisplaySpaces
            
            ForEach(spaces, id: \.id) { space in
                let isCurrent = space.id == spaceManager.currentSpaceUUID
                let name = spaceManager.getSpaceName(space.id)
                
                Text(name)
                    .font(.system(size: 11, weight: isCurrent ? .bold : .regular))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        isCurrent
                        ? Color.blue.opacity(0.7)
                        : Color.white.opacity(0.08)
                    )
                    .foregroundColor(isCurrent ? .white : .secondary)
                    .cornerRadius(12)
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
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.15))
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
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = .white
        textField.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        textField.stringValue = text
        
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
        }
        
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
