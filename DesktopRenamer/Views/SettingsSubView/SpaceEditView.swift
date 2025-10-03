import SwiftUI

// MARK: - Space Edit View
struct SpaceEditView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @State private var desktopSpaces: [DesktopSpace] = []
    
    var body: some View {
        VStack(spacing: 0) {
            if desktopSpaces.isEmpty {
                emptyStateView
            } else {
                tableHeader
                spaceTable
            }
        }
        .padding()
        .onAppear(perform: refreshData)
        .onReceive(spaceManager.$spaceNameDict) { _ in refreshData() }
        .onReceive(spaceManager.$currentSpaceUUID) { _ in refreshData() }
    }
    
    // MARK: - Subviews
    
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
    
    private var tableHeader: some View {
        HStack {
            Text(NSLocalizedString("Settings.Spaces", comment: ""))
                .font(.headline)
            Spacer()
            Text(String(format: NSLocalizedString("Settings.Spaces.Count", comment: ""), desktopSpaces.count))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 12)
    }
    
    private var spaceTable: some View {
        Table(desktopSpaces) {
            TableColumn("#") { space in
                spaceNumberView(for: space)
            }
            .width(30)
            
            TableColumn(NSLocalizedString("Settings.Spaces.Edit.Name", comment: "")) { space in
                spaceNameEditor(for: space)
            }
            .width(220)
            
            TableColumn(NSLocalizedString("Settings.Spaces.Edit.Actions", comment: "")) { space in
                actionButtons(for: space)
            }
            .width(67)
        }
    }
    
    // MARK: - Component Views
    
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
                get: { space.customName },
                set: { newValue in
                    // async to solve last char is deleted
                    DispatchQueue.main.async {
                        updateSpaceName(space, newValue)
                    }
                }
            )
        )
        .textFieldStyle(.roundedBorder)
        .disabled(isCurrentSpace(space))
    }
    
    private func actionButtons(for space: DesktopSpace) -> some View {
        HStack(spacing: 8) {
            moveUpButton(for: space)
            moveDownButton(for: space)
            deleteButton(for: space)
        }
        .buttonStyle(.borderless)
    }
    
    private func moveUpButton(for space: DesktopSpace) -> some View {
        Button(action: { moveRowUp(space) }) {
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .medium))
        }
        .disabled(isFirstRow(space) || isCurrentSpace(space))
        .help(isFirstRow(space) || isCurrentSpace(space)
              ? NSLocalizedString("Settings.Spaces.Edit.Help.MoveUp.Cannot", comment: "")
              : NSLocalizedString("Settings.Spaces.Edit.Help.MoveUp", comment: ""))
    }
    
    private func moveDownButton(for space: DesktopSpace) -> some View {
        Button(action: { moveRowDown(space) }) {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .medium))
        }
        .disabled(isLastRow(space) || isCurrentSpace(space))
        .help(isLastRow(space) || isCurrentSpace(space)
              ? NSLocalizedString("Settings.Spaces.Edit.Help.MoveDown.Cannot", comment: "")
              : NSLocalizedString("Settings.Spaces.Edit.Help.MoveDown", comment: ""))
    }
    
    private func deleteButton(for space: DesktopSpace) -> some View {
        Button(action: { deleteRow(space) }) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isCurrentSpace(space) ? .gray : .red)
        }
        .disabled(isCurrentSpace(space))
        .help(isCurrentSpace(space)
              ? NSLocalizedString("Settings.Spaces.Edit.Help.Delete.Cannot", comment: "")
              : NSLocalizedString("Settings.Spaces.Edit.Help.Delete", comment: ""))
    }
    
    // MARK: - Helper Methods
    
    private func spaceNumberText(for space: DesktopSpace) -> String {
        isCurrentSpace(space) ? "[\(space.num)]" : "\(space.num)"
    }
    
    private func defaultName(for space: DesktopSpace) -> String {
        String(format: NSLocalizedString("Space.DefaultName", comment: ""), space.num)
    }
    
    private func isCurrentSpace(_ space: DesktopSpace) -> Bool {
        space.id == spaceManager.currentSpaceUUID
    }
    
    private func isFirstRow(_ space: DesktopSpace) -> Bool {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }) else { return true }
        return index == 0
    }
    
    private func isLastRow(_ space: DesktopSpace) -> Bool {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }) else { return true }
        return index == desktopSpaces.count - 1
    }
    
    // MARK: - Data Operations
    
    private func refreshData() {
        desktopSpaces = spaceManager.spaceNameDict.sorted { $0.num < $1.num }
    }
    
    private func moveRowUp(_ space: DesktopSpace) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }),
              index > 0 else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            desktopSpaces.swapAt(index, index - 1)
            updateNumbersAndSave()
        }
    }
    
    private func moveRowDown(_ space: DesktopSpace) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }),
              index < desktopSpaces.count - 1 else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            desktopSpaces.swapAt(index, index + 1)
            updateNumbersAndSave()
        }
    }
    
    private func deleteRow(_ space: DesktopSpace) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }),
              !isCurrentSpace(space) else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            desktopSpaces.remove(at: index)
            updateNumbersAndSave()
        }
    }
    
    private func updateSpaceName(_ space: DesktopSpace, _ newName: String) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }) else { return }
        
        var updatedSpace = desktopSpaces[index]
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSpace.customName = trimmedName
        desktopSpaces[index] = updatedSpace
        
        // Update data
        spaceManager.spaceNameDict = desktopSpaces
        spaceManager.saveSpaces()
        
        // Force refresh
        refreshData()
    }
    
    private func updateNumbersAndSave() {
        // Reindex with animation
        for (index, _) in desktopSpaces.enumerated() {
            desktopSpaces[index].num = index + 1
        }
        
        // Sync back to spaceManager
        spaceManager.spaceNameDict = desktopSpaces
        spaceManager.currentTotalSpace = desktopSpaces.count
        spaceManager.saveSpaces()
        
        // Force refresh
        refreshData()
    }
}
