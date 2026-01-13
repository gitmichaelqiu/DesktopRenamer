import SwiftUI

struct SpaceEditView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    
    var body: some View {
        VStack(spacing: 0) {
            if spaceManager.spaceNameDict.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(groupedDisplayIDs, id: \.self) { displayID in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(displayID)
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
            let num1 = extractDisplayNumber(from: id1)
            let num2 = extractDisplayNumber(from: id2)
            if num1 != num2 { return num1 < num2 }
            return id1 < id2
        }
    }
    
    private func extractDisplayNumber(from id: String) -> Int {
        guard let start = id.lastIndex(of: "("),
              let end = id.lastIndex(of: ")"),
              start < end else { return Int.max }
        let numberString = id[id.index(after: start)..<end]
        return Int(numberString) ?? Int.max
    }
    
    private func spaces(for displayID: String) -> [DesktopSpace] {
        spaceManager.spaceNameDict.filter { $0.displayID == displayID }.sorted { $0.num < $1.num }
    }
    
    private func spacesStack(for displayID: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("#").frame(width: 30, alignment: .leading)
                Text(NSLocalizedString("Settings.Spaces.Edit.Name", comment: "")).frame(maxWidth: .infinity, alignment: .leading)
                Text(NSLocalizedString("Settings.Spaces.Edit.Actions", comment: "")).frame(width: 60, alignment: .trailing)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            let displaySpaces = spaces(for: displayID)
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
                set: { newValue in updateSpaceName(space, newValue) }
            )
        )
        .textFieldStyle(.roundedBorder)
    }
    
    private func actionButtons(for space: DesktopSpace, in displayList: [DesktopSpace]) -> some View {
        HStack(spacing: 4) {
            moveUpButton(for: space, list: displayList)
            moveDownButton(for: space, list: displayList)
            deleteButton(for: space)
        }
        .buttonStyle(.borderless)
    }
    
    private func moveUpButton(for space: DesktopSpace, list: [DesktopSpace]) -> some View {
        let isFirst = list.first?.id == space.id
        return Button(action: { moveRowUp(space) }) {
            Image(systemName: "chevron.up").frame(width: 16, height: 16)
        }
        .disabled(isFirst || spaceManager.detectionMethod == .automatic)
        .opacity(isFirst || spaceManager.detectionMethod == .automatic ? 0.3 : 1.0)
    }
    
    private func moveDownButton(for space: DesktopSpace, list: [DesktopSpace]) -> some View {
        let isLast = list.last?.id == space.id
        return Button(action: { moveRowDown(space) }) {
            Image(systemName: "chevron.down").frame(width: 16, height: 16)
        }
        .disabled(isLast || spaceManager.detectionMethod == .automatic)
        .opacity(isLast || spaceManager.detectionMethod == .automatic ? 0.3 : 1.0)
    }
    
    private func deleteButton(for space: DesktopSpace) -> some View {
        Button(action: { deleteRow(space) }) {
            Image(systemName: "trash").frame(width: 16, height: 16)
                .foregroundColor(isCurrentSpace(space) ? Color.secondary : .red)
        }
        .disabled(isCurrentSpace(space) || spaceManager.detectionMethod == .automatic)
        .opacity(isCurrentSpace(space) || spaceManager.detectionMethod == .automatic ? 0.3 : 1.0)
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
    
    private func moveRowUp(_ space: DesktopSpace) {
        guard spaceManager.detectionMethod != .automatic else { return }
        var allSpaces = spaceManager.spaceNameDict
        let siblings = allSpaces.filter { $0.displayID == space.displayID }.sorted { $0.num < $1.num }
        guard let currentIndex = siblings.firstIndex(where: { $0.id == space.id }), currentIndex > 0 else { return }
        let prevSpace = siblings[currentIndex - 1]
        if let idx1 = allSpaces.firstIndex(where: { $0.id == space.id }), let idx2 = allSpaces.firstIndex(where: { $0.id == prevSpace.id }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                let tempNum = allSpaces[idx1].num
                allSpaces[idx1].num = allSpaces[idx2].num
                allSpaces[idx2].num = tempNum
                saveAndRefresh(allSpaces)
            }
        }
    }
    
    private func moveRowDown(_ space: DesktopSpace) {
        guard spaceManager.detectionMethod != .automatic else { return }
        var allSpaces = spaceManager.spaceNameDict
        let siblings = allSpaces.filter { $0.displayID == space.displayID }.sorted { $0.num < $1.num }
        guard let currentIndex = siblings.firstIndex(where: { $0.id == space.id }), currentIndex < siblings.count - 1 else { return }
        let nextSpace = siblings[currentIndex + 1]
        if let idx1 = allSpaces.firstIndex(where: { $0.id == space.id }), let idx2 = allSpaces.firstIndex(where: { $0.id == nextSpace.id }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                let tempNum = allSpaces[idx1].num
                allSpaces[idx1].num = allSpaces[idx2].num
                allSpaces[idx2].num = tempNum
                saveAndRefresh(allSpaces)
            }
        }
    }
    
    private func deleteRow(_ space: DesktopSpace) {
        guard spaceManager.detectionMethod != .automatic else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            var allSpaces = spaceManager.spaceNameDict
            allSpaces.removeAll(where: { $0.id == space.id })
            let displayID = space.displayID
            var siblings = allSpaces.filter { $0.displayID == displayID }.sorted { $0.num < $1.num }
            for (index, _) in siblings.enumerated() { siblings[index].num = index + 1 }
            allSpaces.removeAll(where: { $0.displayID == displayID })
            allSpaces.append(contentsOf: siblings)
            saveAndRefresh(allSpaces)
        }
    }
    
    private func updateSpaceName(_ space: DesktopSpace, _ newName: String) {
        guard let index = spaceManager.spaceNameDict.firstIndex(where: { $0.id == space.id }) else { return }
        spaceManager.spaceNameDict[index].customName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        spaceManager.saveSpaces()
    }
    
    private func saveAndRefresh(_ newSpaces: [DesktopSpace]) {
        spaceManager.spaceNameDict = newSpaces
        spaceManager.saveSpaces()
    }
}
