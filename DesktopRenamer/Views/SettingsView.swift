import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, space, labels, sswitch, permissions, about

    var id: String { self.rawValue }

    var localizedName: LocalizedStringKey {
        switch self {
        case .general: return "Settings.General"
        case .space: return "Settings.Spaces"
        case .labels: return "Settings.Labels"
        case .sswitch: return "Settings.Switch"
        case .permissions: return "Permissions"
        case .about: return "Settings.About"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .space: return "macwindow"
        case .labels: return "tag"
        case .sswitch: return "arrow.left.and.right.square"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

// Layout Constants
let sidebarWidth: CGFloat = 180
let defaultSettingsWindowWidth = 750
let defaultSettingsWindowHeight = 550
let sidebarRowHeight: CGFloat = 32
let sidebarFontSize: CGFloat = 16

// Tighter Header Height
let titleHeaderHeight: CGFloat = 48

struct SettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    // Inject GestureManager
    @EnvironmentObject var gestureManager: GestureManager

    @State private var selectedTab: SettingsTab? = .general

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle("")
        .modifier(ToolbarHider())
        .edgesIgnoringSafeArea(.top)
        .frame(
            width: CGFloat(defaultSettingsWindowWidth), height: CGFloat(defaultSettingsWindowHeight)
        )
    }

    struct ToolbarHider: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 14.0, *) {
                content.toolbar(.hidden, for: .windowToolbar)
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if #available(macOS 14.0, *) {
            List(selection: $selectedTab) {
                Section {
                    ForEach(SettingsTab.allCases) { tab in
                        sidebarItem(for: tab)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 45)
                        Text("Desktop").font(.system(size: 28, weight: .heavy)).foregroundStyle(
                            .primary)
                        Text("Renamer").font(.system(size: 28, weight: .heavy)).foregroundStyle(
                            .primary
                        ).padding(.bottom, 20)
                    }
                }
                .collapsible(false)
            }
            .scrollDisabled(true)
            .removeSidebarToggle()
            .navigationSplitViewColumnWidth(
                min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth
            )
            .edgesIgnoringSafeArea(.top)
        } else {
            List(selection: $selectedTab) {
                Section {
                    ForEach(SettingsTab.allCases) { tab in
                        sidebarItem(for: tab)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 45)
                        Text("Desktop").font(.system(size: 28, weight: .heavy)).foregroundStyle(
                            .primary)
                        Text("Renamer").font(.system(size: 28, weight: .heavy)).foregroundStyle(
                            .primary
                        ).padding(.bottom, 20)
                    }
                }
                .collapsible(false)
            }
            .scrollDisabled(true)
            .navigationSplitViewColumnWidth(
                min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth
            )
            .listStyle(.sidebar)
            .edgesIgnoringSafeArea(.top)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                if let tab = selectedTab {
                    switch tab {
                    case .general:
                        GeneralSettingsView(spaceManager: spaceManager, labelManager: labelManager)
                    case .space:
                        SpaceEditView(spaceManager: spaceManager, labelManager: labelManager)
                    case .labels:
                        LabelSettingsView(labelManager: labelManager)
                    case .sswitch:
                        SwitchSettingsView()
                    case .permissions:
                        PermissionsSettingsView()
                    case .about:
                        AboutView()
                    }
                } else {
                    Text("Select a category").foregroundColor(.secondary).frame(
                        maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, titleHeaderHeight)

            if let tab = selectedTab {
                VStack(spacing: 0) {
                    HStack {
                        Text(tab.localizedName).font(.system(size: 20, weight: .semibold)).padding(
                            .leading, 20)
                        Spacer()
                    }
                    .frame(height: titleHeaderHeight)
                    .background(.bar)
                    Divider()
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .edgesIgnoringSafeArea(.top)
    }

    @ViewBuilder
    private func sidebarItem(for tab: SettingsTab) -> some View {
        NavigationLink(value: tab) {
            Label {
                Text(tab.localizedName).font(.system(size: sidebarFontSize, weight: .medium))
                    .padding(.leading, 2)
            } icon: {
                Image(systemName: tab.iconName).resizable().scaledToFit().frame(
                    height: sidebarRowHeight - 15)
            }
        }
        .frame(height: sidebarRowHeight)
    }
}

class SettingsHostingController: NSHostingController<AnyView> {
    private let spaceManager: SpaceManager
    private let labelManager: SpaceLabelManager
    private let hotkeyManager: HotkeyManager
    private let gestureManager: GestureManager

    // Updated Init signature
    init(
        spaceManager: SpaceManager, labelManager: SpaceLabelManager, hotkeyManager: HotkeyManager,
        gestureManager: GestureManager
    ) {
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        self.hotkeyManager = hotkeyManager
        self.gestureManager = gestureManager

        let rootView = SettingsView(spaceManager: spaceManager, labelManager: labelManager)
            .environmentObject(hotkeyManager)
            .environmentObject(gestureManager)  // Inject GestureManager

        super.init(rootView: AnyView(rootView))
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.preferredContentSize = NSSize(
            width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight)
    }
}
