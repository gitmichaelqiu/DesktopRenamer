import Foundation
import AppKit
import Combine
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
    var fingerId: Int32    // previously unknown1
    var handId: Int32      // previously unknown2
    var normalizedVector: MTVector
    var size: Float
    var unknown1: Int32    // previously unknown3
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector // previously unknown4 (MTPoint) -> Fixed to MTVector (4 floats)
    var unknown2: Int32    // previously unknown5
    var unknown3: Int32    // New field to match padding/layout
    var unknown4: Float    // previously unknown6
}

// Private Framework Loading
private let MTSFrameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

// Function Pointers
private var _MTDeviceCreateList: (@convention(c) () -> Unmanaged<CFArray>)?
private var _MTDeviceCreateFromService: (@convention(c) (io_service_t) -> MTDeviceRef)?
private var _MTRegisterContactFrameCallback: (@convention(c) (MTDeviceRef, @convention(c) (MTDeviceRef, UnsafeMutableRawPointer, Int32, Double, Int32) -> Void, Int32) -> Void)?
private var _MTDeviceStart: (@convention(c) (MTDeviceRef, Int32) -> Void)?
private var _MTDeviceStop: (@convention(c) (MTDeviceRef, Int32) -> Void)?

// MARK: - 2. Gesture Manager
class GestureManager: ObservableObject {
    // Settings
    private let kGestureEnabled = "GestureManager.Enabled"
    private let kFingerCount = "GestureManager.FingerCount"
    
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
    
    private weak var spaceManager: SpaceManager?
    private var devices: [MTDeviceRef] = []
    
    // IOKit State
    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    
    // Tracking State
    fileprivate static var sharedManager: GestureManager?
    private var lastSwitchTime: TimeInterval = 0
    private var initialX: Float? = nil
    private var previousX: Float? = nil
    private var swipeDetectedInCurrentTouchSession = false
    
    // Tuning
    private let switchCooldown: TimeInterval = 0.6
    private let minSwipeDistance: Float = 0.15
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        self.isEnabled = UserDefaults.standard.object(forKey: kGestureEnabled) == nil ? false : UserDefaults.standard.bool(forKey: kGestureEnabled)
        
        let savedCount = UserDefaults.standard.integer(forKey: kFingerCount)
        self.fingerCount = (savedCount == 3 || savedCount == 4) ? savedCount : 3
        
        GestureManager.sharedManager = self
        
        loadPrivateFramework()
        
        if isEnabled {
            startMonitoring()
        }
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func updateState() {
        if isEnabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
    
    // MARK: - Private API Loading
    private func loadPrivateFramework() {
        guard let handle = dlopen(MTSFrameworkPath, RTLD_NOW) else {
            print("Failed to load MultitouchSupport.framework at \(MTSFrameworkPath)")
            return
        }
        
        // Bind C functions
        if let sym = dlsym(handle, "MTDeviceCreateList") {
            _MTDeviceCreateList = unsafeBitCast(sym, to: (@convention(c) () -> Unmanaged<CFArray>).self)
        }
        if let sym = dlsym(handle, "MTDeviceCreateFromService") {
            _MTDeviceCreateFromService = unsafeBitCast(sym, to: (@convention(c) (io_service_t) -> MTDeviceRef).self)
        }
        if let sym = dlsym(handle, "MTRegisterContactFrameCallback") {
            _MTRegisterContactFrameCallback = unsafeBitCast(sym, to: (@convention(c) (MTDeviceRef, @convention(c) (MTDeviceRef, UnsafeMutableRawPointer, Int32, Double, Int32) -> Void, Int32) -> Void).self)
        }
        if let sym = dlsym(handle, "MTDeviceStart") {
            _MTDeviceStart = unsafeBitCast(sym, to: (@convention(c) (MTDeviceRef, Int32) -> Void).self)
        }
        if let sym = dlsym(handle, "MTDeviceStop") {
            _MTDeviceStop = unsafeBitCast(sym, to: (@convention(c) (MTDeviceRef, Int32) -> Void).self)
        }
    }
    
    // MARK: - Device Management
    private func startMonitoring() {
        // 1. Try standard list creation first
        if let createList = _MTDeviceCreateList {
            let deviceList = createList().takeRetainedValue() as? [MTDeviceRef] ?? []
            for device in deviceList {
                setupDevice(device)
            }
        }
        
        // 2. Setup IOKit listener for hot-plugging / manual discovery
        setupIOKitListener()
        
        print("GestureManager: Started monitoring. Current devices: \(devices.count)")
    }
    
    private func stopMonitoring() {
        // Stop MT Devices
        guard let stopDevice = _MTDeviceStop else { return }
        for device in devices {
            stopDevice(device, 0)
        }
        devices.removeAll()
        
        // Clean up IOKit
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
        // Prevent duplicate registration
        if !devices.contains(device) {
            devices.append(device)
            if let registerCallback = _MTRegisterContactFrameCallback,
               let startDevice = _MTDeviceStart {
                registerCallback(device, mtCallback, 0)
                startDevice(device, 0)
                print("GestureManager: Registered device \(device)")
            }
        }
    }
    
    // MARK: - IOKit Listener
    private func setupIOKitListener() {
        guard notifyPort == nil else { return }
        
        let port = IONotificationPortCreate(kIOMasterPortDefault)
        self.notifyPort = port
        
        guard let runLoopSource = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else { return }
        // Use CommonModes to ensure callbacks fire even during UI tracking
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
            // Iterate once to arm the listener and add existing devices
            consumeIterator(addedIterator)
        } else {
            print("GestureManager: Failed to register IOKit notification.")
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
        
        // 1. Validate Finger Count
        guard numFingers == self.fingerCount else {
            // Reset state if fingers lift or count changes
            if numFingers == 0 {
                initialX = nil
                previousX = nil
                swipeDetectedInCurrentTouchSession = false
            }
            return
        }
        
        // 2. Cooldown & Session Check
        if now - lastSwitchTime < switchCooldown { return }
        if swipeDetectedInCurrentTouchSession { return }
        
        // 3. Calculate Average X Position (Centroid)
        // Note: MTTouch x is normalized (0.0 to 1.0)
        let totalX = touches.reduce(0) { $0 + $1.normalizedVector.position.x }
        let currentAvgX = totalX / Float(numFingers)
        
        // 4. Initialize Start Position
        if initialX == nil {
            initialX = currentAvgX
            previousX = currentAvgX
            return
        }
        
        guard let startX = initialX else { return }
        
        // 5. Detect Swipe Distance
        let delta = currentAvgX - startX
        
        // 6. Trigger Logic
        if abs(delta) > minSwipeDistance {
            if delta < 0 {
                // Fingers moved LEFT -> Go to NEXT space
                print("GestureManager: Swipe Left Detected (Next Space)")
                triggerSwitch(direction: .next)
            } else {
                // Fingers moved RIGHT -> Go to PREVIOUS space
                print("GestureManager: Swipe Right Detected (Previous Space)")
                triggerSwitch(direction: .previous)
            }
            
            swipeDetectedInCurrentTouchSession = true
        }
        
        previousX = currentAvgX
    }
    
    enum SwitchDirection {
        case next
        case previous
    }
    
    private func triggerSwitch(direction: SwitchDirection) {
        lastSwitchTime = Date().timeIntervalSince1970
        
        DispatchQueue.main.async {
            guard let sm = self.spaceManager else { return }
            switch direction {
            case .next:
                sm.switchToNextSpace()
            case .previous:
                sm.switchToPreviousSpace()
            }
        }
    }
}

// MARK: - Global C Callbacks

// IOKit Callback
private let ioKitCallback: @convention(c) (UnsafeMutableRawPointer?, io_iterator_t) -> Void = { (refCon, iterator) in
    guard let refCon = refCon else { return }
    let manager = Unmanaged<GestureManager>.fromOpaque(refCon).takeUnretainedValue()
    manager.consumeIterator(iterator)
}

// Multitouch Callback
private func mtCallback(device: MTDeviceRef, touchPointer: UnsafeMutableRawPointer, numFingers: Int32, timestamp: Double, frame: Int32) {
    guard let manager = GestureManager.sharedManager, manager.isEnabled else { return }
    
    let typedPointer = touchPointer.assumingMemoryBound(to: MTTouch.self)
    let buffer = UnsafeBufferPointer(start: typedPointer, count: Int(numFingers))
    let touches = Array(buffer)
    
    // Debug print to confirm callback is firing
    // print("MTCallback: Fingers: \(numFingers)")
    
    let validTouches = touches.filter { $0.state > 0 && $0.state < 7 }
    
    if !validTouches.isEmpty {
        manager.handleTouches(touches: validTouches, numFingers: Int(numFingers))
    } else {
        manager.handleTouches(touches: [], numFingers: 0)
    }
}
