import AppKit
import SwiftUI

/// Shared geometry for every launcher row and submenu.
enum LauncherLayout {
    static let rowIconSlot: CGFloat = 24
    static let rowHorizontalPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 6
    static let rowSpacing: CGFloat = 10

    static let submenuWidth: CGFloat = 380
    static let submenuPanelPadding: CGFloat = 6
    static let submenuCornerRadius: CGFloat = 16
    static let submenuIconSlot: CGFloat = 18
    static let submenuIconSymbolSize: CGFloat = 15
    static let submenuActionIconSlot: CGFloat = 16
    static let submenuActionIconSymbolSize: CGFloat = 13
    static let submenuHeaderIconSlot: CGFloat = 28
    static let submenuHeaderSpacing: CGFloat = 10
    static let submenuRowContentSpacing: CGFloat = 6
    static let submenuHeaderHorizontalPadding: CGFloat = submenuRowHorizontalPadding
    static let submenuHeaderVerticalPadding: CGFloat = 8
    static let submenuSeparatorSpacing: CGFloat = 6
    static let submenuRowHorizontalPadding: CGFloat = 8
    static let submenuRowHeight: CGFloat = 36
    static let submenuRowSpacing: CGFloat = 1
    static let submenuSearchFieldHeight: CGFloat = 24
    static let submenuSearchHorizontalPadding: CGFloat = 8
    static let submenuSearchVerticalPadding: CGFloat = 6

    static let listTopPadding: CGFloat = 4
    static let listBottomPadding: CGFloat = 8
    static let listHorizontalPadding: CGFloat = 8
    static let sectionHeaderSpacing: CGFloat = 10
    static let sectionHeaderBottomPadding: CGFloat = 4

    static let bottomBarCapsulePadding: CGFloat = 4
    static let bottomBarControlHorizontalPadding: CGFloat = 8
    static let bottomBarControlHeight: CGFloat = 28
    static let bottomBarHorizontalPadding: CGFloat = 8
    static let bottomBarVerticalPadding: CGFloat = 6
    static let bottomBarHeight: CGFloat = 52

    static let keycapSide: CGFloat = 18
    static let keycapCornerRadius: CGFloat = 6
    static let commandNumberIndicatorSide: CGFloat = 22
}

/// Shared typography for the launcher surface, following Raycast's title/trailing-label hierarchy.
enum LauncherTypography {
    static let rowTitle = Font.body
    static let rowTrailing = Font.callout
    static let sectionHeader = Font.subheadline.weight(.medium)
    static let submenuHeader = Font.callout
    static let submenuRow = Font.body
    static let bar = Font.callout.weight(.medium)
    static let keycap = Font.caption
}

/// A fixed-size icon slot keeps symbols and application icons optically aligned.
struct LauncherIconSlot: View {
    private enum Source {
        case symbol(String)
        case image(NSImage)
    }

    private let source: Source
    private let tint: Color
    private let symbolSize: CGFloat
    private let slot: CGFloat

    init(
        systemName: String,
        tint: Color = .primary,
        symbolSize: CGFloat = 17,
        slot: CGFloat = LauncherLayout.rowIconSlot
    ) {
        source = .symbol(systemName)
        self.tint = tint
        self.symbolSize = symbolSize
        self.slot = slot
    }

    init(image: NSImage, slot: CGFloat = LauncherLayout.rowIconSlot) {
        source = .image(image)
        tint = .primary
        symbolSize = 17
        self.slot = slot
    }

    var body: some View {
        Group {
            switch source {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: symbolSize, weight: .medium))
                    .foregroundStyle(tint)
            case .image(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: slot, height: slot)
    }
}

/// The secondary text used for owners, space metadata, and right-side row labels.
struct LauncherTrailingLabel: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(LauncherTypography.rowTrailing)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// Raycast-style status label used for window state and staged-action metadata.
struct LauncherStatusLabel: View {
    let text: String
    let color: Color
    let background: Color

    init(text: String, color: Color, background: Color? = nil) {
        self.text = text
        self.color = color
        self.background = background ?? color.opacity(0.15)
    }

    var body: some View {
        Text(text)
            .font(LauncherTypography.rowTrailing)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: LauncherLayout.keycapCornerRadius, style: .continuous)
                    .fill(background)
            )
    }
}

/// A shared selection/hover surface for the primary launcher lists.
struct LauncherRowSurface: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let colors = ThemeColors(isDark: colorScheme == .dark)
        content
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? colors.rowSelection : (isHovered ? colors.rowHover : .clear))
            }
    }
}

extension View {
    func launcherRowSurface(isSelected: Bool, isHovered: Bool) -> some View {
        modifier(LauncherRowSurface(isSelected: isSelected, isHovered: isHovered))
    }
}

/// Raycast-style outlined keycap chips. Compound shortcuts are split into separate chips.
struct KeycapView: View {
    let text: String
    let isSelected: Bool
    var isGreenRow: Bool = false
    var verticalPadding: CGFloat = 1
    var horizontalPadding: CGFloat = 4
    @Environment(\.colorScheme) var colorScheme

    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    private var tokens: [String] {
        if text.contains(" ") {
            return text.split(separator: " ").map(String.init)
        }
        if text.count > 1 && text.contains(where: { "⌘⌥⇧⌃".contains($0) }) {
            return text.map(String.init)
        }
        return [text]
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                Text(verbatim: token)
                    .font(LauncherTypography.keycap)
                    .foregroundStyle(isSelected && isGreenRow ? .white : colors.textSecondary)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .frame(minWidth: LauncherLayout.keycapSide, minHeight: LauncherLayout.keycapSide)
                    .background {
                        RoundedRectangle(
                            cornerRadius: LauncherLayout.keycapCornerRadius, style: .continuous
                        )
                        .fill(isSelected && isGreenRow ? Color.white.opacity(0.16) : .clear)
                    }
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: LauncherLayout.keycapCornerRadius, style: .continuous
                        )
                        .stroke(colors.border, lineWidth: 1)
                    }
            }
        }
    }
}

/// A compact Raycast-style command number that floats over the row's trailing content.
struct LauncherCommandNumberIndicator: View {
    let number: Int
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LauncherLayout.keycapCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(isDark ? 0.22 : 0.12))

            Text(verbatim: "\(number)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary)
        }
            .frame(
                width: LauncherLayout.commandNumberIndicatorSide,
                height: LauncherLayout.commandNumberIndicatorSide
            )
            .compositingGroup()
            .shadow(
                color: Color.black.opacity(isDark ? 0.55 : 0.28),
                radius: 4,
                x: 0,
                y: 2
            )
            .accessibilityLabel(Text("Command \(number)"))
    }
}

/// Positions command numbers over the existing trailing labels without changing row layout.
struct LauncherCommandNumberOverlay: ViewModifier {
    let number: Int?
    let trailingPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if let number {
                    LauncherCommandNumberIndicator(number: number)
                        .padding(.trailing, trailingPadding)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func launcherCommandNumberOverlay(
        _ number: Int?,
        trailingPadding: CGFloat = LauncherLayout.rowHorizontalPadding
    ) -> some View {
        modifier(
            LauncherCommandNumberOverlay(
                number: number,
                trailingPadding: trailingPadding
            )
        )
    }
}

/// Shared header layout for the Cmd+K actions menu and all space-selection submenus.
struct LauncherSubmenuHeader<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LauncherLayout.submenuHeaderHorizontalPadding)
            .padding(.vertical, LauncherLayout.submenuHeaderVerticalPadding)
    }
}

/// The canonical window heading shared by Cmd+K actions and move-to-space menus.
struct LauncherSubmenuWindowHeader: View {
    let window: WindowEntry
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    var body: some View {
        HStack(spacing: LauncherLayout.submenuHeaderSpacing) {
            LauncherIconSlot(
                image: NSWorkspace.shared.icon(forFile: window.appPath),
                slot: LauncherLayout.submenuHeaderIconSlot
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? String(localized: "(No Title)") : window.title)
                    .font(LauncherTypography.rowTitle)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)

                LauncherTrailingLabel(window.ownerName, color: colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
    }
}

/// A text-only submenu heading for space selection modes without a source window.
struct LauncherSubmenuTitleHeader: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(LauncherTypography.submenuHeader)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// A separator with explicit clearance so the first selected row cannot touch the line.
struct LauncherSubmenuSeparator: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = ThemeColors(isDark: colorScheme == .dark)
        Rectangle()
            .fill(colors.separator)
            .frame(height: 1)
            .padding(.vertical, LauncherLayout.submenuSeparatorSpacing)
    }
}

/// The filter field belongs to the open submenu, leaving the root query untouched.
enum LauncherSubmenuSearchKind {
    case actions
    case spaces
}

struct LauncherSubmenuSearchField: View {
    @ObservedObject var viewModel: LauncherViewModel
    let kind: LauncherSubmenuSearchKind
    let placeholder: String
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }

    var body: some View {
        SearchTextField(
            text: $viewModel.submenuSearchQuery,
            isDark: colors.isDark,
            isSubmenuField: true,
            onUpArrow: selectPrevious,
            onDownArrow: selectNext,
            onLeftArrow: { false },
            onRightArrow: { false },
            onEnter: executeSelection,
            onCommandEnter: executeSelection,
            onCommandNumber: executeNumberedSelection,
            onTab: {},
            onEscape: dismissSubmenu,
            onKeyEquivalent: { _ in false },
            placeholder: placeholder,
            textFieldFont: NSFont.systemFont(ofSize: 14, weight: .regular),
            textFieldColor: .labelColor,
            placeholderColor: .secondaryLabelColor,
            usesSingleLineMode: true,
            focusNotificationName: NSNotification.Name("FocusLauncherSubmenuTextField")
        )
        .frame(height: LauncherLayout.submenuSearchFieldHeight)
        .padding(.horizontal, LauncherLayout.submenuSearchHorizontalPadding)
        .padding(.vertical, LauncherLayout.submenuSearchVerticalPadding)
    }

    private func selectPrevious() {
        switch kind {
        case .actions:
            viewModel.selectPreviousCommandKAction()
        case .spaces:
            viewModel.isKeyboardSelection = true
            viewModel.spaceMenuSelectedIndex = max(viewModel.spaceMenuSelectedIndex - 1, 0)
        }
    }

    private func selectNext() {
        switch kind {
        case .actions:
            viewModel.selectNextCommandKAction()
        case .spaces:
            viewModel.isKeyboardSelection = true
            viewModel.spaceMenuSelectedIndex = min(
                viewModel.spaceMenuSelectedIndex + 1,
                max(viewModel.spaceMenuSpaces.count - 1, 0)
            )
        }
    }

    private func executeSelection() {
        switch kind {
        case .actions:
            viewModel.executeCommandKAction()
        case .spaces:
            viewModel.executeSpaceMenuSelection()
        }
    }

    private func executeNumberedSelection(_ number: Int) {
        let index = number - 1
        switch kind {
        case .actions:
            guard viewModel.commandKActions.indices.contains(index) else { return }
            viewModel.commandKSelectedIndex = index
            viewModel.executeCommandKAction()
        case .spaces:
            guard viewModel.spaceMenuSpaces.indices.contains(index) else { return }
            viewModel.spaceMenuSelectedIndex = index
            viewModel.executeSpaceMenuSelection()
        }
    }

    private func dismissSubmenu() {
        switch kind {
        case .actions:
            viewModel.commandKTargetWindow = nil
        case .spaces:
            viewModel.handleEscapeKey()
        }
    }
}

/// Shared frosted panel chrome for every launcher submenu.
struct LauncherSubmenuPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(LauncherLayout.submenuPanelPadding)
            .frame(width: LauncherLayout.submenuWidth)
            .launcherFrosted(
                in: RoundedRectangle(
                    cornerRadius: LauncherLayout.submenuCornerRadius, style: .continuous
                )
            )
    }
}

/// Shared selectable row chrome for submenu items.
struct LauncherSubmenuRow<Content: View>: View {
    let isSelected: Bool
    let commandNumber: Int?
    let action: () -> Void
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    init(
        isSelected: Bool,
        commandNumber: Int? = nil,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.commandNumber = commandNumber
        self.action = action
        self.content = content()
    }

    var body: some View {
        let colors = ThemeColors(isDark: colorScheme == .dark)
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LauncherLayout.submenuRowHorizontalPadding)
                .frame(height: LauncherLayout.submenuRowHeight, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? colors.rowSelection : (isHovered ? colors.rowHover : .clear))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .launcherCommandNumberOverlay(
            commandNumber,
            trailingPadding: LauncherLayout.submenuRowHorizontalPadding
        )
        .onHover { isHovered = $0 }
    }
}
