import SwiftUI

struct SpaceEditView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @State private var desktopSpaces: [DesktopSpace] = []
    
    var body: some View {
        VStack(spacing: 0) {
            if desktopSpaces.isEmpty {
                emptyStateView
            } else {
                // We use a List to allow for native-looking sections
                // Alternatively, we could use ScrollView + VStack if we want distinct Tables
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(groupedDisplayIDs, id: \.self) { displayID in
                            VStack(alignment: .leading, spacing: 8) {
                                // Section Header
                                Text(displayID)
                                    .font(.headline)
                                    .padding(.leading, 4)
                                
                                // Table for this display
                                displaySpecificTable(for: displayID)
                                    .frame(height: calculateTableHeight(for: displayID))
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear(perform: refreshData)
        .onReceive(spaceManager.$spaceNameDict) { _ in refreshData() }
        .onReceive(spaceManager.$currentSpaceUUID) { _ in refreshData() }
    }
    
    // Computed property to get unique display IDs
    private var groupedDisplayIDs: [String] {
        Array(Set(desktopSpaces.map { $0.displayID })).sorted()
    }
    
    private func spaces(for displayID: String) -> [DesktopSpace] {
        desktopSpaces.filter { $0.displayID == displayID }.sorted { $0.num < $1.num }
    }
    
    private func calculateTableHeight(for displayID: String) -> CGFloat {
        // Rough estimation: Header (30) + Row (30) * Count.
        // Min height 60, Max height constrained by window, but ScrollView handles overflow.
        let count = spaces(for: displayID).count
        return CGFloat(30 + (count * 30))
    }
    
    // Subviews
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "macwindow")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("Settings.Spaces.Edit.Empty.Title", comment: ""))
                .font(.headline)
            Text(NSLocalizedString("Settings.Spaces.Edit.Empty.Hint", comment: ""))
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private func displaySpecificTable(for displayID: String) -> some View {
        let displaySpaces = spaces(for: displayID)
        
        return Table(displaySpaces) {
            TableColumn("#") { space in
                spaceNumberView(for: space)
            }
            .width(30)
            
            TableColumn(NSLocalizedString("Settings.Spaces.Edit.Name", comment: "")) { space in
                spaceNameEditor(for: space)
            }
            .width(220)
            
            TableColumn(NSLocalizedString("Settings.Spaces.Edit.Actions", comment: "")) { space in
                actionButtons(for: space, in: displaySpaces)
            }
            .width(67)
        }
        .scrollDisabled(true) // We let the parent ScrollView handle scrolling
    }
    
    // Component Views
    
    private func spaceNumberView(for space: DesktopSpace) -> some View {
        Text(spaceNumberText(for: space))
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity)
            .foregroundColor(isCurrentSpace(space) ? .accentColor : .primary)
    }
    
    private func spaceNameEditor(for space: DesktopSpace) -> some View {
        TextField(
            defaultName(for: space),
            text: Binding(
                get: {
                    spaceManager.spaceNameDict.first(where: { $0.id == space.id })?.customName ?? space.customName
                },
                set: { newValue in
                    DispatchQueue.main.async {
                        updateSpaceName(space, newValue)
                    }
                }
            )
        )
        .textFieldStyle(.roundedBorder)
    }
    
    private func actionButtons(for space: DesktopSpace, in displayList: [DesktopSpace]) -> some View {
        HStack(spacing: 8) {
            moveUpButton(for: space, list: displayList)
            moveDownButton(for: space, list: displayList)
            deleteButton(for: space)
        }
        .buttonStyle(.borderless)
    }
    
    private func moveUpButton(for space: DesktopSpace, list: [DesktopSpace]) -> some View {
        let isFirst = list.first?.id == space.id
        return Button(action: { moveRowUp(space) }) {
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .medium))
        }
        .disabled(isFirst)
    }
    
    private func moveDownButton(for space: DesktopSpace, list: [DesktopSpace]) -> some View {
        let isLast = list.last?.id == space.id
        return Button(action: { moveRowDown(space) }) {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .medium))
        }
        .disabled(isLast)
    }
    
    private func deleteButton(for space: DesktopSpace) -> some View {
        Button(action: { deleteRow(space) }) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isCurrentSpace(space) ? Color(.disabledControlTextColor) : .red)
        }
        .disabled(isCurrentSpace(space))
    }
    
    // Helper Methods
    
    private func spaceNumberText(for space: DesktopSpace) -> String {
        isCurrentSpace(space) ? "[\(space.num)]" : "\(space.num)"
    }
    
    private func defaultName(for space: DesktopSpace) -> String {
        String(format: NSLocalizedString("Space.DefaultName", comment: ""), space.num)
    }
    
    private func isCurrentSpace(_ space: DesktopSpace) -> Bool {
        space.id == spaceManager.currentSpaceUUID
    }
    
    // Data Operations
    
    private func refreshData() {
        desktopSpaces = spaceManager.spaceNameDict
    }
    
    private func moveRowUp(_ space: DesktopSpace) {
        // Find the full list
        var allSpaces = spaceManager.spaceNameDict
        
        // Find siblings in the SAME display
        let siblings = allSpaces.filter { $0.displayID == space.displayID }.sorted { $0.num < $1.num }
        
        guard let currentIndex = siblings.firstIndex(where: { $0.id == space.id }),
              currentIndex > 0 else { return }
        
        let prevSpace = siblings[currentIndex - 1]
        
        // Swap their NUMBERS
        if let idx1 = allSpaces.firstIndex(where: { $0.id == space.id }),
           let idx2 = allSpaces.firstIndex(where: { $0.id == prevSpace.id }) {
            
            let tempNum = allSpaces[idx1].num
            allSpaces[idx1].num = allSpaces[idx2].num
            allSpaces[idx2].num = tempNum
            
            saveAndRefresh(allSpaces)
        }
    }
    
    private func moveRowDown(_ space: DesktopSpace) {
        var allSpaces = spaceManager.spaceNameDict
        let siblings = allSpaces.filter { $0.displayID == space.displayID }.sorted { $0.num < $1.num }
        
        guard let currentIndex = siblings.firstIndex(where: { $0.id == space.id }),
              currentIndex < siblings.count - 1 else { return }
        
        let nextSpace = siblings[currentIndex + 1]
        
        if let idx1 = allSpaces.firstIndex(where: { $0.id == space.id }),
           let idx2 = allSpaces.firstIndex(where: { $0.id == nextSpace.id }) {
            
            let tempNum = allSpaces[idx1].num
            allSpaces[idx1].num = allSpaces[idx2].num
            allSpaces[idx2].num = tempNum
            
            saveAndRefresh(allSpaces)
        }
    }
    
    private func deleteRow(_ space: DesktopSpace) {
        var allSpaces = spaceManager.spaceNameDict
        
        // Remove the item
        allSpaces.removeAll(where: { $0.id == space.id })
        
        // Re-number siblings in that display
        let displayID = space.displayID
        var siblings = allSpaces.filter { $0.displayID == displayID }.sorted { $0.num < $1.num }
        
        for (index, _) in siblings.enumerated() {
            siblings[index].num = index + 1
        }
        
        // Merge back into main list
        // 1. Remove all old siblings from main list
        allSpaces.removeAll(where: { $0.displayID == displayID })
        // 2. Add updated siblings back
        allSpaces.append(contentsOf: siblings)
        
        saveAndRefresh(allSpaces)
    }
    
    private func updateSpaceName(_ space: DesktopSpace, _ newName: String) {
        guard let index = spaceManager.spaceNameDict.firstIndex(where: { $0.id == space.id }) else { return }
        var allSpaces = spaceManager.spaceNameDict
        allSpaces[index].customName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        saveAndRefresh(allSpaces)
    }
    
    private func saveAndRefresh(_ newSpaces: [DesktopSpace]) {
        spaceManager.spaceNameDict = newSpaces
        spaceManager.saveSpaces()
        refreshData()
    }
}
