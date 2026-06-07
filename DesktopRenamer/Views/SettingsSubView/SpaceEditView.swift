import SwiftUI

struct SpaceEditView: View {
    @ObservedObject var spaceManager: SpaceManager
    @EnvironmentObject var navigationState: SettingsNavigationState
    
    var body: some View {
        VStack(spacing: 0) {
            if spaceManager.spaceNameDict.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(groupedDisplayIDs, id: \.self) { displayID in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(resolveDisplayName(for: displayID))
                                    .font(.headline)
                                    .padding(.leading, 4)
                                
                                spacesStack(for: displayID)
                                    .cornerRadius(8)
                                    .padding(.bottom, 10)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 40)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: spaceManager.spaceNameDict)
        .onAppear {
            navigationState.register(title: "Settings.Spaces.Edit.Name", tab: .space, keywords: ["rename", "name", "title", "label", "custom", "edit"])
            navigationState.register(title: "Settings.Spaces.Edit.Actions", tab: .space, keywords: ["reorder", "arrange", "display", "monitor", "position"])
        }
        .onDisappear {
            navigationState.unregister(title: "Settings.Spaces.Edit.Name", tab: .space)
            navigationState.unregister(title: "Settings.Spaces.Edit.Actions", tab: .space)
        }
        .environment(\.settingsTab, .space)
    }
    
    private var sectionBackgroundColor: Color {
        let nsColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.20, alpha: 1.0)
            } else {
                return NSColor(calibratedWhite: 1.00, alpha: 1.0)
            }
        }
        return Color(nsColor: nsColor)
    }
    
    private var groupedDisplayIDs: [String] {
        let ids = Array(Set(spaceManager.spaceNameDict.map { $0.displayID }))
        return ids.sorted { id1, id2 in
            if id1 == "Main" { return true }
            if id2 == "Main" { return false }
            let name1 = resolveDisplayName(for: id1)
            let name2 = resolveDisplayName(for: id2)
            return name1 < name2
        }
    }
    
    private func resolveDisplayName(for displayID: String) -> String {
        // Handle "Main" legacy identifier.
        if displayID == "Main" { return "Main Display" }
        
        // Attempt to match screen by UUID.
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                let cgsID = screenNumber.uint32Value
                if let uuidRef = CGDisplayCreateUUIDFromDisplayID(cgsID) {
                    let uuid = uuidRef.takeRetainedValue()
                    if let uuidStr = CFUUIDCreateString(nil, uuid) as String? {
                        // Check if the input is a UUID and it matches this screen
                        if uuidStr.caseInsensitiveCompare(displayID) == .orderedSame {
                            return screen.localizedName
                        }
                    }
                }
            }
        }
        
        // Fallback for legacy "Name (ID)" format.
        if displayID.contains("(") && displayID.contains(")") {
             if let lastParenIndex = displayID.lastIndex(of: "(") {
                return String(displayID[..<lastParenIndex]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return displayID
    }
    
    private func spaces(for displayID: String) -> [DesktopSpace] {
        // Filter to regular desktops only; fullscreen apps are excluded from manual editing.
        return spaceManager.spaceNameDict
            .filter { $0.displayID == displayID && !$0.isFullscreen }
            .sorted { $0.num < $1.num }
    }
    
    private func spacesStack(for displayID: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("#").frame(width: 30, alignment: .leading)
                Text(NSLocalizedString("Settings.Spaces.Edit.Name", comment: ""))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("Settings.Spaces.Edit.Name")
                Text(NSLocalizedString("Settings.Spaces.Edit.Actions", comment: ""))
                    .frame(width: 60, alignment: .trailing)
                    .id("Settings.Spaces.Edit.Actions")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            let displaySpaces = spaces(for: displayID)
            
            if displaySpaces.isEmpty {
                Text("No editable spaces (fullscreen only)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(10)
            } else {
                ForEach(displaySpaces) { space in
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            spaceNumberView(for: space).frame(width: 30, alignment: .leading)
                            spaceNameEditor(for: space).frame(maxWidth: .infinity)
                            actionButtons(for: space, in: displaySpaces).frame(width: 60, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        
                        if space.id != displaySpaces.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(sectionBackgroundColor.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
        )
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "macwindow").font(.system(size: 48)).foregroundColor(.secondary)
            Text(NSLocalizedString("Settings.Spaces.Edit.Empty.Title", comment: "")).font(.headline)
            Text(NSLocalizedString("Settings.Spaces.Edit.Empty.Hint", comment: "")).font(.body).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
    
    private func spaceNumberView(for space: DesktopSpace) -> some View {
        Text(spaceNumberText(for: space))
            .font(.system(.body, design: .monospaced))
            .foregroundColor(isCurrentSpace(space) ? .accentColor : .primary)
            .fontWeight(isCurrentSpace(space) ? .bold : .regular)
    }
    
    private func spaceNameEditor(for space: DesktopSpace) -> some View {
        TextField(
            defaultName(for: space),
            text: Binding(
                get: { spaceManager.spaceNameDict.first(where: { $0.id == space.id })?.customName ?? space.customName },
                set: { newValue in 
                    let sanitized = newValue.replacingOccurrences(of: "~", with: "")
                    updateSpaceName(space, sanitized) 
                }
            )
        )
        .textFieldStyle(.roundedBorder)
    }
    
    private func actionButtons(for space: DesktopSpace, in displayList: [DesktopSpace]) -> some View {
        HStack(spacing: 4) {
            lockButton(for: space)
        }
        .buttonStyle(.borderless)
    }

    private func lockButton(for space: DesktopSpace) -> some View {
        let isLocked = spaceManager.lockedSpaceIDs.contains(space.id)
        return Button(action: {
            spaceManager.toggleLockSpace(space.id)
        }) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isLocked ? .accentColor : .secondary)
                .frame(width: 16, height: 16)
        }
        .help(isLocked ? "Unlock space" : "Lock current space")
    }
    
    private func spaceNumberText(for space: DesktopSpace) -> String {
        isCurrentSpace(space) ? "[\(space.num)]" : "\(space.num)"
    }
    
    private func defaultName(for space: DesktopSpace) -> String {
        String(format: NSLocalizedString("Space.DefaultName", comment: ""), space.num)
    }
    
    private func isCurrentSpace(_ space: DesktopSpace) -> Bool {
        space.id == spaceManager.currentSpaceUUID
    }
    
    
    private func updateSpaceName(_ space: DesktopSpace, _ newName: String) {
        spaceManager.renameSpace(space.id, to: newName)
    }
    
}
