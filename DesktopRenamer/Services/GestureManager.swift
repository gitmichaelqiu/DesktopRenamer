import AppKit
import Combine
import Foundation
import IOKit

// MARK: - 1. Private MultitouchSupport Definitions

private typealias MTDeviceRef = OpaquePointer

// Helper structs to replace tuples for C-compatibility
private struct MTPoint {
    var x: Float
    var y: Float
}

private struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

// Structure representing a single finger touch
// Updated to match standard 64-bit layout (~92-96 bytes) to correct stride issues
private struct MTTouch {
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
private let MTSFrameworkPath =
    "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

// Function Pointers
private var _MTDeviceCreateList: (@convention(c) () -> Unmanaged<CFArray>)?
private var _MTDeviceCreateFromService: (@convention(c) (io_service_t) -> MTDeviceRef)?
private var _MTRegisterContactFrameCallback:
    (
        @convention(c) (
            MTDeviceRef,
            @convention(c) (MTDeviceRef, UnsafeMutableRawPointer, Int32, Double, Int32) -> Void,
            Int32
        ) -> Void
    )?
private var _MTDeviceStart: (@convention(c) (MTDeviceRef, Int32) -> Void)?
private var _MTDeviceStop: (@convention(c) (MTDeviceRef, Int32) -> Void)?

// MARK: - 2. Gesture Manager
class GestureManager: ObservableObject {
    // Settings
    private let kGestureEnabled = "GestureManager.Enabled"
    private let kFingerCount = "GestureManager.FingerCount"
    private let kSwitchOverride = "GestureManager.SwitchOverride"
    private let kSwipeThreshold = "GestureManager.SwipeThreshold"

    public enum SwitchOverrideMode: String, CaseIterable, Identifiable {
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

    private weak var spaceManager: SpaceManager?
    private var devices: [MTDeviceRef] = []

    // IOKit State
    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0

    // Tracking State
    fileprivate static var sharedManager: GestureManager?

    // Replaced single centroid point with per-finger tracking for consistency checks
    private var initialTouchPositions: [Int32: MTPoint] = [:]

    private var lastTouchTime: TimeInterval = 0
    private var lastSwitchTime: TimeInterval = 0

    // Direction Lock
    private var lockedDirection: SwitchDirection? = nil

    // Tuning
    private let switchCooldown: TimeInterval = 0.25
    // private let minSwipeDistance: Float = 0.10 // Moved to swipeThreshold
    private let consistencyThreshold: Float = 0.01  // 5% Minimum movement per finger (Anti-Tap)
    private let touchTimeout: TimeInterval = 0.15

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

        GestureManager.sharedManager = self

        loadPrivateFramework()

        // Start monitoring always because we need it to intercept macOS switching gestures for hideWhenSwitching,
        // even if the switch override feature itself is conceptually "disabled".
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func updateState() {
        // Now monitoring is always on to support label hiding.
        // We do not stop monitoring when `isEnabled` becomes false.
    }

    // MARK: - Private API Loading
    private func loadPrivateFramework() {
        guard let handle = dlopen(MTSFrameworkPath, RTLD_NOW) else {
            print("Failed to load MultitouchSupport.framework at \(MTSFrameworkPath)")
            return
        }

        // Bind C functions
        if let sym = dlsym(handle, "MTDeviceCreateList") {
            _MTDeviceCreateList = unsafeBitCast(
                sym, to: (@convention(c) () -> Unmanaged<CFArray>).self)
        }
        if let sym = dlsym(handle, "MTDeviceCreateFromService") {
            _MTDeviceCreateFromService = unsafeBitCast(
                sym, to: (@convention(c) (io_service_t) -> MTDeviceRef).self)
        }
        if let sym = dlsym(handle, "MTRegisterContactFrameCallback") {
            _MTRegisterContactFrameCallback = unsafeBitCast(
                sym,
                to: (@convention(c) (
                    MTDeviceRef,
                    @convention(c) (MTDeviceRef, UnsafeMutableRawPointer, Int32, Double, Int32) ->
                        Void, Int32
                ) -> Void).self)
        }
        if let sym = dlsym(handle, "MTDeviceStart") {
            _MTDeviceStart = unsafeBitCast(
                sym, to: (@convention(c) (MTDeviceRef, Int32) -> Void).self)
        }
        if let sym = dlsym(handle, "MTDeviceStop") {
            _MTDeviceStop = unsafeBitCast(
                sym, to: (@convention(c) (MTDeviceRef, Int32) -> Void).self)
        }
    }

    // MARK: - Device Management
    private func startMonitoring() {
        if let createList = _MTDeviceCreateList {
            let deviceList = createList().takeRetainedValue() as? [MTDeviceRef] ?? []
            for device in deviceList {
                setupDevice(device)
            }
        }
        setupIOKitListener()
        print("GestureManager: Started monitoring. Current devices: \(devices.count)")
    }

    private func stopMonitoring() {
        guard let stopDevice = _MTDeviceStop else { return }
        for device in devices {
            stopDevice(device, 0)
        }
        devices.removeAll()

        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }

        print("GestureManager: Stopped monitoring.")
    }

    private func setupDevice(_ device: MTDeviceRef) {
        if !devices.contains(device) {
            devices.append(device)
            if let registerCallback = _MTRegisterContactFrameCallback,
                let startDevice = _MTDeviceStart
            {
                registerCallback(device, mtCallback, 0)
                startDevice(device, 0)
                print("GestureManager: Registered device \(device)")
            }
        }
    }

    // MARK: - IOKit Listener
    private func setupIOKitListener() {
        guard notifyPort == nil else { return }

        let port = IONotificationPortCreate(kIOMainPortDefault)
        self.notifyPort = port

        guard let runLoopSource = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue()
        else { return }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        let matchingDict = IOServiceMatching("AppleMultitouchDevice")

        let context = Unmanaged.passUnretained(self).toOpaque()

        let result = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            matchingDict,
            ioKitCallback,
            context,
            &addedIterator
        )

        if result == kIOReturnSuccess {
            consumeIterator(addedIterator)
        }
    }

    fileprivate func consumeIterator(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let createFromService = _MTDeviceCreateFromService {
                let device = createFromService(service)
                setupDevice(device)
            }
            IOObjectRelease(service)
        }
    }

    // MARK: - Handling Logic
    fileprivate func handleTouches(touches: [MTTouch], numFingers: Int) {
        let now = Date().timeIntervalSince1970

        // 0. Timeout Check
        if now - lastTouchTime > touchTimeout {
            resetTrackingState()
        }
        lastTouchTime = now

        // 1. Validate Finger Count
        guard numFingers == self.fingerCount else {
            resetTrackingState()
            return
        }

        // 2. Validate Touches (Sanity Check)
        for touch in touches {
            if touch.normalizedVector.position.x < 0 || touch.normalizedVector.position.x > 1.0 {
                resetTrackingState()
                return
            }
        }

        // 3. Initialize Start Position (Per Finger)
        if initialTouchPositions.isEmpty {
            for touch in touches {
                initialTouchPositions[touch.identifier] = touch.normalizedVector.position
            }
            return
        }

        // 4. Validate Continuity
        // Ensure the fingers on the pad match the IDs we started tracking
        let currentIDs = Set(touches.map { $0.identifier })
        let initialIDs = Set(initialTouchPositions.keys)

        if currentIDs != initialIDs {
            resetTrackingState()
            return
        }

        // Cooldown Check
        if now - lastSwitchTime < switchCooldown {
            return
        }

        // 5. Calculate Average Deltas
        var totalDX: Float = 0
        var totalDY: Float = 0

        for touch in touches {
            guard let startPos = initialTouchPositions[touch.identifier] else { continue }
            totalDX += (touch.normalizedVector.position.x - startPos.x)
            totalDY += (touch.normalizedVector.position.y - startPos.y)
        }

        let avgDX = totalDX / Float(numFingers)
        let avgDY = totalDY / Float(numFingers)

        // 6. Pre-Trigger Logic: Overscroll Indicator
        var isOverscroll = false

        // Only check horizontal dominance for indicator first
        if abs(avgDX) > abs(avgDY) {
            let direction: SwitchDirection = avgDX < 0 ? .next : .previous

            // Determine target display to check boundaries
            var targetDisplayID: String? = nil
            if self.switchOverride == .cursor {
                targetDisplayID = SpaceHelper.getCursorDisplayID()
            }
            // If .activeWindow, we leave nil, relying on SpaceManager's default context

            if direction == .previous {
                if spaceManager?.isFirstSpace(onDisplayID: targetDisplayID) == true {
                    isOverscroll = true
                    // avgDX is positive here.
                    let progress = Double(abs(avgDX) / swipeThreshold)
                    // Previous means going "Left". Wall is on Left. Edge is .leading.
                    DispatchQueue.main.async {
                        OverscrollOverlayManager.shared.update(progress: progress, edge: .leading)
                    }
                }
            } else {  // .next
                if spaceManager?.isLastSpace(onDisplayID: targetDisplayID) == true {
                    isOverscroll = true
                    // avgDX is negative here.
                    let progress = Double(abs(avgDX) / swipeThreshold)
                    // Next means going "Right". Wall is on Right. Edge is .trailing.
                    DispatchQueue.main.async {
                        OverscrollOverlayManager.shared.update(progress: progress, edge: .trailing)
                    }
                }
            }
        }

        if isOverscroll {
            return
        } else {
            DispatchQueue.main.async {
                OverscrollOverlayManager.shared.hide()
            }
        }

        // 7. Trigger Logic
        // Primary threshold check
        if abs(avgDX) > swipeThreshold {

            // Check for Horizontal Dominance (Must be more horizontal than vertical)
            if abs(avgDX) > abs(avgDY) {

                let direction: SwitchDirection = avgDX < 0 ? .next : .previous

                // 7. Consistency Check (Anti-Tap Protection)
                // REQUIRE that EVERY finger has moved significantly in the target direction.
                // A tap usually has one finger anchor or fingers moving in opposition.
                var isConsistent = true

                for touch in touches {
                    guard let startPos = initialTouchPositions[touch.identifier] else { continue }
                    let dx = touch.normalizedVector.position.x - startPos.x

                    if direction == .next {
                        // Expect negative movement (Left Swipe)
                        // If any finger moved less than threshold (e.g. -0.01 or +0.1), fail.
                        if dx > -consistencyThreshold {
                            isConsistent = false
                            break
                        }
                    } else {
                        // Expect positive movement (Right Swipe)
                        if dx < consistencyThreshold {
                            isConsistent = false
                            break
                        }
                    }
                }

                if isConsistent {
                    // Lock Direction for this session
                    if lockedDirection == nil {
                        lockedDirection = direction
                    }

                    // Only act if matches locked direction
                    if lockedDirection == direction {
                        print("GestureManager: Triggered \(direction)")

                        // Fire a nil-target SpaceSwitchRequested so SpaceLabelManager can hide all active Preview Labels
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SpaceSwitchRequested"), object: nil)

                        triggerSwitch(direction: direction)

                        // CRITICAL: Reset anchors to current position to allow consecutive swipes
                        initialTouchPositions.removeAll()
                        for touch in touches {
                            initialTouchPositions[touch.identifier] =
                                touch.normalizedVector.position
                        }
                    }
                }
            }
        }
    }

    private func resetTrackingState() {
        initialTouchPositions.removeAll()
        lockedDirection = nil

        DispatchQueue.main.async {
            OverscrollOverlayManager.shared.hide()
        }
    }

    enum SwitchDirection {
        case next
        case previous
    }

    private func triggerSwitch(direction: SwitchDirection) {
        lastSwitchTime = Date().timeIntervalSince1970
        guard let sm = spaceManager, self.isEnabled else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            var targetDisplayID: String? = nil

            if self.switchOverride == .cursor {
                targetDisplayID = SpaceHelper.getCursorDisplayID()
            }
            // If .activeWindow, we pass nil, which causes SpaceManager to default to the currently active display

            switch direction {
            case .next:
                sm.switchToNextSpace(onDisplayID: targetDisplayID)
            case .previous:
                sm.switchToPreviousSpace(onDisplayID: targetDisplayID)
            }
        }
    }
}

// MARK: - Global C Callbacks

private let ioKitCallback: @convention(c) (UnsafeMutableRawPointer?, io_iterator_t) -> Void = {
    (refCon, iterator) in
    guard let refCon = refCon else { return }
    let manager = Unmanaged<GestureManager>.fromOpaque(refCon).takeUnretainedValue()
    manager.consumeIterator(iterator)
}

private func mtCallback(
    device: MTDeviceRef, touchPointer: UnsafeMutableRawPointer, numFingers: Int32,
    timestamp: Double, frame: Int32
) {
    guard let manager = GestureManager.sharedManager else { return }

    let typedPointer = touchPointer.assumingMemoryBound(to: MTTouch.self)
    let buffer = UnsafeBufferPointer(start: typedPointer, count: Int(numFingers))
    let touches = Array(buffer)

    // Valid states: 1 (Hover/Range), 2 (Touching), 3 (Dragging), 4 (Lifting)
    let validTouches = touches.filter { $0.state > 0 && $0.state < 7 }

    // Calculate count from valid array, ignore raw numFingers if it mismatches active states
    let activeCount = validTouches.count

    if activeCount > 0 {
        manager.handleTouches(touches: validTouches, numFingers: activeCount)
    } else {
        // Send 0 to force reset
        manager.handleTouches(touches: [], numFingers: 0)
    }
}
