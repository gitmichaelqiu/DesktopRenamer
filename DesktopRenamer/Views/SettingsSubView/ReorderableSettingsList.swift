import SwiftUI

struct ReorderableSettingsRowContext {
    let index: Int
    let isLast: Bool
}

struct ReorderableSettingsList<Item: Identifiable, RowContent: View, DragPreview: View>: View where Item.ID == String {
    let items: [Item]
    let rowContent: (Item, ReorderableSettingsRowContext) -> RowContent
    let dragPreview: (Item) -> DragPreview
    let moveBefore: (String, String) -> Bool
    let moveToEnd: (String) -> Void

    @State private var targetedItemID: String?

    init(
        items: [Item],
        @ViewBuilder rowContent: @escaping (Item, ReorderableSettingsRowContext) -> RowContent,
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
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    decoratedRow(
                        for: item,
                        context: ReorderableSettingsRowContext(index: index, isLast: index == items.count - 1)
                    )
                }
                .reorderable()
            }
            .reorderContainer(for: Item.self) { difference in
                applyNativeReorder(difference)
            }
        } else {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                decoratedRow(
                    for: item,
                    context: ReorderableSettingsRowContext(index: index, isLast: index == items.count - 1)
                )
                    .draggable(item.id) {
                        dragPreview(item)
                            .background(SettingsSectionStyle.dragPreviewBackgroundColor)
                    }
                    .dropDestination(for: String.self) { sourceIDs, _ in
                        guard let sourceID = sourceIDs.first,
                              sourceID != item.id,
                              items.contains(where: { $0.id == sourceID }) else { return false }
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

    private func decoratedRow(for item: Item, context: ReorderableSettingsRowContext) -> some View {
        rowContent(item, context)
            .contentShape(Rectangle())
            .contentShape(.dragPreview, Rectangle())
            .overlay(
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
