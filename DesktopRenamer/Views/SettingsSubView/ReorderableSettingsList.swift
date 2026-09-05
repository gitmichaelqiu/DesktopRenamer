import SwiftUI

struct ReorderableSettingsList<Item: Identifiable, RowContent: View, DragPreview: View>: View where Item.ID == String {
    let items: [Item]
    let rowContent: (Item, [Item]) -> RowContent
    let dragPreview: (Item) -> DragPreview
    let moveBefore: (String, String) -> Bool
    let moveToEnd: (String) -> Void

    @State private var targetedItemID: String?

    init(
        items: [Item],
        @ViewBuilder rowContent: @escaping (Item, [Item]) -> RowContent,
        @ViewBuilder dragPreview: @escaping (Item) -> DragPreview,
        moveBefore: @escaping (String, String) -> Bool,
        moveToEnd: @escaping (String) -> Void
    ) {
        self.items = items
        self.rowContent = rowContent
        self.dragPreview = dragPreview
        self.moveBefore = moveBefore
        self.moveToEnd = moveToEnd
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 27.0, *) {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    decoratedRow(for: item)
                }
                .reorderable()
            }
            .reorderContainer(for: Item.self) { difference in
                applyNativeReorder(difference)
            }
        } else {
            ForEach(items) { item in
                decoratedRow(for: item)
                    .draggable(item.id) {
                        dragPreview(item)
                    }
                    .dropDestination(for: String.self) { sourceIDs, _ in
                        guard let sourceID = sourceIDs.first else { return false }
                        return moveBefore(sourceID, item.id)
                    } isTargeted: { isTargeted in
                        if isTargeted {
                            targetedItemID = item.id
                        } else if targetedItemID == item.id {
                            targetedItemID = nil
                        }
                    }
            }
        }
    }

    private func decoratedRow(for item: Item) -> some View {
        rowContent(item, items)
            .contentShape(Rectangle())
            .contentShape(.dragPreview, Rectangle())
            .background(Color(nsColor: NSColor.controlBackgroundColor))
            .background(
                targetedItemID == item.id
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @available(macOS 27.0, *)
    private func applyNativeReorder(
        _ difference: ReorderDifference<String, ReorderableSingleCollectionIdentifier>
    ) {
        guard let sourceID = difference.sources.first else { return }

        switch difference.destination.position {
        case .before(let targetID):
            _ = moveBefore(sourceID, targetID)
        case .end:
            moveToEnd(sourceID)
        }
    }
}
