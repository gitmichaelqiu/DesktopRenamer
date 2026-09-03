import AppKit
import Combine
import Foundation
import IOKit

typealias MTDeviceRef = OpaquePointer

struct MTPoint {
    var x: Float
    var y: Float
}

struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

// Structure representing a single finger touch event from the multitouch sensor.
// Note: Updated to 64-bit layout (~92-96 bytes) to resolve memory alignment and stride issues.
struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerId: Int32  // previously unknown1
    var handId: Int32  // previously unknown2
    var normalizedVector: MTVector
    var size: Float
    var unknown1: Int32  // previously unknown3
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector  // previously unknown4
    var unknown2: Int32  // previously unknown5
    var unknown3: Int32  // New field
    var unknown4: Float  // previously unknown6
}

// Private Framework Loading
let MTSFrameworkPath =
    "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

// Function Pointers
var _MTDeviceCreateList: (@convention(c) () -> Unmanaged<CFArray>)?
var _MTDeviceCreateFromService: (@convention(c) (io_service_t) -> MTDeviceRef)?
var _MTRegisterContactFrameCallback:
    (
        @convention(c) (
            MTDeviceRef,
            @convention(c) (MTDeviceRef, UnsafeMutableRawPointer, Int32, Double, Int32) -> Void,
            Int32
        ) -> Void
    )?
var _MTDeviceStart: (@convention(c) (MTDeviceRef, Int32) -> Void)?
var _MTDeviceStop: (@convention(c) (MTDeviceRef, Int32) -> Void)?

// Core service responsible for intercepting and interpreting trackpad gestures.
class GestureManager: ObservableObject {
    // Settings
    let kGestureEnabled = "GestureManager.Enabled"
    let kFingerCount = "GestureManager.FingerCount"
    let kSwitchOverride = "GestureManager.SwitchOverride"
    let kSwipeThreshold = "GestureManager.SwipeThreshold"
    let kMoveWindowOnOption = "GestureManager.MoveWindowOnOption"
    let kSwitchDuration = "GestureManager.SwitchDuration"

    public enum SwitchOverrideMode: String, CaseIterable, Identifiable, Equatable {
        case cursor = "Cursor"
        case activeWindow = "Active Window"

        public var id: String { rawValue }
    }

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: kGestureEnabled)
            updateState()
        }
    }

    @Published var fingerCount: Int {
        didSet {
            UserDefaults.standard.set(fingerCount, forKey: kFingerCount)
        }
    }

    @Published var switchOverride: SwitchOverrideMode {
        didSet {
            UserDefaults.standard.set(switchOverride.rawValue, forKey: kSwitchOverride)
        }
    }

    @Published var swipeThreshold: Float {
        didSet {
            UserDefaults.standard.set(swipeThreshold, forKey: kSwipeThreshold)
        }
    }

    @Published var moveWindowOnOption: Bool {
        didSet {
            UserDefaults.standard.set(moveWindowOnOption, forKey: kMoveWindowOnOption)
        }
    }

    /// User-configured target switch duration in seconds.
    /// 0 = instant mode (no calibration, fixed high velocity).
    /// Range: 0.0 – 1.0, default 0.35.
    @Published var switchDuration: TimeInterval {
        didSet {
            UserDefaults.standard.set(switchDuration, forKey: kSwitchDuration)
        }
    }

    weak var spaceManager: SpaceManager?
    var devices: [MTDeviceRef] = []

    // IOKit notification state for hardware lifecycle management.
    var notifyPort: IONotificationPortRef?
    var addedIterator: io_iterator_t = 0

    // Internal state for active gesture tracking.
    static var sharedManager: GestureManager?
    static var lastTrackpadSwipeTime: TimeInterval = 0

    // Per-finger tracking is used instead of a single centroid to allow for consistency verification.
    var initialTouchPositions: [Int32: MTPoint] = [:]

    var lastTouchTime: TimeInterval = 0
    var lastSwitchTime: TimeInterval = 0

    // The multitouch callback can outpace the main queue while WindowServer
    // is reconciling a space. Keep the callback lightweight and allow only
    // one main-queue action at a time. A later request replaces the pending
    // direction and is resumed after the current SpaceHelper transaction is
    // settled.
    let gestureSwitchStateLock = NSLock()
    var isGestureSwitchActionScheduled = false
    var isGestureSwitchOperationInFlight = false
    var isGestureSwitchTransactionActive = false
    var pendingGestureSwitchDirection: SwitchDirection?
    var gestureSwitchResumeWorkItem: DispatchWorkItem?
    var programmaticSwitchFinishedObserver: NSObjectProtocol?

    // Boundary checks are used only for the overscroll affordance. Cache the
    // result during a short touch sequence instead of querying CGS for every
    // multitouch frame, which can otherwise delay the actual switch request.
    var cachedBoundaryDisplayID: String?
    var cachedBoundaryDirection: SwitchDirection?
    var cachedBoundaryMode: SwitchOverrideMode?
    var cachedBoundaryValue = false
    var cachedBoundaryTime: TimeInterval = 0
    let boundaryCacheDuration: TimeInterval = 0.12
    var boundaryRefreshWorkItem: DispatchWorkItem?
    var boundaryRefreshGeneration = 0

    // These values are written by the multitouch callback and are used to
    // avoid enqueueing redundant overlay updates on the main queue.
    var isOverscrollIndicatorActive = false
    var lastOverscrollDirection: SwitchDirection?
    var lastOverscrollProgress: Double = 0
    var overscrollUpdateWorkItem: DispatchWorkItem?
    var overscrollUpdateGeneration = 0

    // Gesture direction locking to prevent oscillation during a single swipe.
    var lockedDirection: SwitchDirection? = nil

    // Sensitivity and timing configuration.
    let switchCooldown: TimeInterval = 0.15
    // private let minSwipeDistance: Float = 0.10 // Moved to swipeThreshold
    let consistencyThreshold: Float = 0.01  // 5% Minimum movement per finger (Anti-Tap)
    let touchTimeout: TimeInterval = 0.15

    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        self.isEnabled =
            UserDefaults.standard.object(forKey: kGestureEnabled) == nil
            ? false : UserDefaults.standard.bool(forKey: kGestureEnabled)

        let savedCount = UserDefaults.standard.integer(forKey: kFingerCount)
        self.fingerCount = (savedCount == 3 || savedCount == 4) ? savedCount : 3

        let savedOverride = UserDefaults.standard.string(forKey: kSwitchOverride)
        if let savedOverride = savedOverride, let mode = SwitchOverrideMode(rawValue: savedOverride)
        {
            self.switchOverride = mode
        } else {
            self.switchOverride = .cursor
        }

        // Default to 0.10 if not set
        self.swipeThreshold =
            UserDefaults.standard.object(forKey: kSwipeThreshold) == nil
            ? 0.10 : UserDefaults.standard.float(forKey: kSwipeThreshold)

        self.moveWindowOnOption =
            UserDefaults.standard.object(forKey: kMoveWindowOnOption) == nil
            ? false : UserDefaults.standard.bool(forKey: kMoveWindowOnOption)

        self.switchDuration =
            UserDefaults.standard.object(forKey: kSwitchDuration) == nil
            ? 0.30 : UserDefaults.standard.double(forKey: kSwitchDuration)

        GestureManager.sharedManager = self

        programmaticSwitchFinishedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SpaceProgrammaticSwitchFinished"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.schedulePendingGestureSwitchResume()
        }

        loadPrivateFramework()

        // Start monitoring always because we need it to intercept macOS switching gestures for hideWhenSwitching,
        // even if the switch override feature itself is conceptually "disabled".
        startMonitoring()
    }

    deinit {
        if let observer = programmaticSwitchFinishedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        gestureSwitchResumeWorkItem?.cancel()
        boundaryRefreshWorkItem?.cancel()
        overscrollUpdateWorkItem?.cancel()
        stopMonitoring()
    }

    private func updateState() {
        // Now monitoring is always on to support label hiding.
        // We do not stop monitoring when `isEnabled` becomes false.
    }

}
