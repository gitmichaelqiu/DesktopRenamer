import Cocoa
import Combine
import QuartzCore

// The floating label window used to display space names.
class SpaceLabelWindow: NSWindow {
    let label: NSTextField
    let handleView: CollapsibleHandleView
    let contentContainer: NSView

    public let spaceId: String
    public let displayID: String
    public let isFullscreenSpace: Bool

    var cancellables = Set<AnyCancellable>()
    let spaceManager: SpaceManager
    weak var labelManager: SpaceLabelManager?
    var isUsingGlassEffect: Bool?
    var contentContainerConstraints: [NSLayoutConstraint] = []

    // State
    var isActiveMode: Bool = true
    var isDragging = false
    var lastDragPoint: NSPoint = .zero
    var pendingVisibilityTask: DispatchWorkItem?
    var isDocked: Bool = true
    var dockEdge: NSRectEdge = .maxX
    var previewSize: NSSize = NSSize(width: 800, height: 500)

    var isInvisibleAnchorMode: Bool = false

    // Constants
    static let baseActiveFontSize: CGFloat = 45
    static let basePreviewFontSize: CGFloat = 180
    static let handleSize = NSSize(width: 32, height: 60)

    var hasOrderedInOnce = false

    static func screen(matching displayID: String) -> NSScreen? {
        let targetID = displayID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return NSScreen.screens.first { screen in
            if targetID.isEmpty || targetID == "MAIN" || targetID == "UNKNOWN" {
                guard let mainScreen = NSScreen.main else { return false }
                return screen === mainScreen
            }

            let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber
            guard let screenNumber else { return false }

            let idString = "\(screen.localizedName) (\(screenNumber))".uppercased()
            if idString == targetID || screen.localizedName.uppercased() == targetID {
                return true
            }

            guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(screenNumber.uint32Value) else {
                return false
            }
            let uuid = uuidRef.takeRetainedValue()
            let uuidString = (CFUUIDCreateString(nil, uuid) as String).uppercased()
            return uuidString == targetID
        }
    }

    var isHiddenCornerMode: Bool {
        return isActiveMode && !(labelManager?.showOnDesktop == true)
    }

    init(
        spaceId: String, name: String, displayID: String, isFullscreen: Bool,
        spaceManager: SpaceManager, labelManager: SpaceLabelManager
    ) {
        self.spaceId = spaceId
        self.displayID = displayID
        self.isFullscreenSpace = isFullscreen
        self.spaceManager = spaceManager
        self.labelManager = labelManager

        // Text Label
        self.label = NSTextField(labelWithString: name)
        self.label.alignment = .center
        self.label.textColor = .labelColor

        // Handle View
        self.handleView = CollapsibleHandleView()
        self.handleView.isHidden = true
        self.handleView.translatesAutoresizingMaskIntoConstraints = false

        // Container View
        self.contentContainer = NSView(frame: .zero)
        self.contentContainer.wantsLayer = true

        self.contentContainer.addSubview(self.label)
        self.contentContainer.addSubview(self.handleView)

        // Pin HandleView to container edges.
        NSLayoutConstraint.activate([
            self.handleView.leadingAnchor.constraint(equalTo: self.contentContainer.leadingAnchor),
            self.handleView.trailingAnchor.constraint(
                equalTo: self.contentContainer.trailingAnchor),
            self.handleView.topAnchor.constraint(equalTo: self.contentContainer.topAnchor),
            self.handleView.bottomAnchor.constraint(equalTo: self.contentContainer.bottomAnchor),
        ])

        // Resolve UUIDs as well as names/numeric IDs before the first frame is
        // assigned. Otherwise a newly connected display's label starts on the
        // main screen and can remain there while Mission Control is settling.
        let foundScreen = Self.screen(matching: displayID)

        let targetScreen = foundScreen ?? NSScreen.main ?? NSScreen.screens.first

        let startRect: NSRect
        if let targetScreen = targetScreen {
            let screenFrame = targetScreen.frame
            startRect = NSRect(
                x: screenFrame.midX - 100, y: screenFrame.midY - 50, width: 200, height: 100)
        } else {
            startRect = NSRect(x: 0, y: 0, width: 200, height: 100)
        }

        super.init(
            contentRect: startRect, styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false)

        self.isReleasedWhenClosed = false

        if targetScreen == nil {
            self.close()
            return
        }

        configureEffectView(force: true)

        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating

        // Collection Behavior
        // Note: .canJoinAllSpaces is excluded as it interferes with space switching.
        // .fullScreenAuxiliary is retained to allow visibility over fullscreen apps.
        // .ignoresCycle prevents label windows from appearing in Alt+Tab window cycling.
        self.collectionBehavior = [.managed, .fullScreenAuxiliary, .ignoresCycle]

        // Observers
        self.spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateName(self.spaceManager.getSpaceName(self.spaceId))
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(repositionWindow),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        syncFromGlobalState()
        setupLiveBackgroundUpdate()

        DispatchQueue.main.async { [weak self] in
            self?.updateLayout(isCurrentSpace: true)
            self?.updateVisibility(animated: false)
            self?.updateInteractivity()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var canBecomeKeyOverride: Bool = false

    // Standard OS window behavior overrides.
    override var canBecomeKey: Bool { return canBecomeKeyOverride }
    override var canBecomeMain: Bool { return canBecomeKeyOverride }

}
