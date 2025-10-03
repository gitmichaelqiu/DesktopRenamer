import SwiftUI

// MARK: - Space Edit View
struct SpaceEditView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @State private var desktopSpaces: [DesktopSpace] = []
    
    var body: some View {
        VStack {
            if desktopSpaces.isEmpty {
                Text("No spaces available")
                    .foregroundColor(.secondary)
            } else {
                Table(desktopSpaces) {
                    TableColumn("#") { space in
                        Text(spaceManager.currentSpaceUUID == space.id ? "[\(space.num)]" : "\(space.num)")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .width(30)
                    
                    TableColumn(NSLocalizedString("Settings.Space.CustomName", comment: "")) { space in
                        TextField(
                            String(format: NSLocalizedString("Space.DefaultName", comment: ""), space.num),
                            text: Binding(
                                get: { space.customName },
                                set: { newValue in
                                    updateSpaceName(space, newValue)
                                }
                            )
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .width(240)
                    
                    TableColumn(NSLocalizedString("Settings.Space.Actions", comment: "")) { space in
                        HStack(spacing: 4) {
                            Button("↑") {
                                moveRowUp(space)
                            }
                            .disabled(isFirstRow(space) || space.id == spaceManager.currentSpaceUUID)
                            
                            Button("↓") {
                                moveRowDown(space)
                            }
                            .disabled(isLastRow(space) || space.id == spaceManager.currentSpaceUUID)
                            
                            Button("⌫") {
                                deleteRow(space)
                            }
                            .disabled(space.id == spaceManager.currentSpaceUUID)
                            .help(space.id == spaceManager.currentSpaceUUID ?
                                  NSLocalizedString("settings.space.cannot_delete_current", comment: "Cannot delete current space") : "")
                        }
                        .buttonStyle(.bordered)
                    }
                    .width(85)
                }
                .tableStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            refreshData()
        }
        .onReceive(spaceManager.$spaceNameDict) { _ in
            refreshData()
        }
        .onReceive(spaceManager.$currentSpaceUUID) { _ in
            refreshData()
        }
    }
    
    private func refreshData() {
        desktopSpaces = spaceManager.spaceNameDict.sorted { $0.num < $1.num }
    }
    
    private func isFirstRow(_ space: DesktopSpace) -> Bool {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }) else { return true }
        return index == 0
    }
    
    private func isLastRow(_ space: DesktopSpace) -> Bool {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }) else { return true }
        return index == desktopSpaces.count - 1
    }
    
    private func moveRowUp(_ space: DesktopSpace) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }),
              index > 0 else { return }
        
        desktopSpaces.swapAt(index, index - 1)
        updateNumbersAndSave()
    }
    
    private func moveRowDown(_ space: DesktopSpace) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }),
              index < desktopSpaces.count - 1 else { return }
        
        desktopSpaces.swapAt(index, index + 1)
        updateNumbersAndSave()
    }
    
    private func deleteRow(_ space: DesktopSpace) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }),
              space.id != spaceManager.currentSpaceUUID else { return }
        
        desktopSpaces.remove(at: index)
        updateNumbersAndSave()
    }
    
    private func updateSpaceName(_ space: DesktopSpace, _ newName: String) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }) else { return }
        
        var updatedSpace = desktopSpaces[index]
        updatedSpace.customName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        desktopSpaces[index] = updatedSpace
        
        spaceManager.spaceNameDict = desktopSpaces
        spaceManager.saveSpaces()
    }
    
    private func updateNumbersAndSave() {
        // Reindex
        for (index, _) in desktopSpaces.enumerated() {
            desktopSpaces[index].num = index + 1
        }
        
        // Sync back to spaceManager
        spaceManager.spaceNameDict = desktopSpaces
        spaceManager.currentTotalSpace = desktopSpaces.count
        spaceManager.saveSpaces()
    }
}
