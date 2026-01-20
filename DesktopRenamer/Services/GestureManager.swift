import Foundation
import AppKit
import Combine
import os

class GestureManager: ObservableObject {
    // MARK: - Settings Keys
    private let kGestureEnabled = "GestureManager.Enabled"
    private let kFingerCount = "GestureManager.FingerCount" // 3 or 4
    
    // MARK: - Published State
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: kGestureEnabled)
            updateMonitoringState()
        }
    }
    
    @Published var fingerCount: Int {
        didSet {
            UserDefaults.standard.set(fingerCount, forKey: kFingerCount)
        }
    }
    
    // MARK: - Internals
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var spaceManager: SpaceManager?
    
    // State for gesture detection
    private var currentDeltaX: CGFloat = 0
    private var lastEventTime: TimeInterval = 0
    private var lastSwitchTime: TimeInterval = 0
    
    // Tuning
    // Lower threshold helps catch quick flicks.
    // High accumulation is needed because scroll events come in small chunks.
    private let swipeThreshold: CGFloat = 80.0
    private let cooldown: TimeInterval = 0.5
    private let resetWindow: TimeInterval = 0.15 // Time gap to consider a new gesture
    
    // Logger
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.desktoprenamer", category: "GestureManager")
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        
        self.isEnabled = UserDefaults.standard.object(forKey: kGestureEnabled) == nil ? false : UserDefaults.standard.bool(forKey: kGestureEnabled)
        let savedCount = UserDefaults.standard.integer(forKey: kFingerCount)
        self.fingerCount = (savedCount == 3 || savedCount == 4) ? savedCount : 3
        
        updateMonitoringState()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func updateMonitoringState() {
        if isEnabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
    
    private func startMonitoring() {
        guard globalMonitor == nil else { return }
        
        logger.info("Starting Gesture Monitoring...")
        
        // 1. Global Monitor (For when app is in background)
        // NOTE: This requires "Input Monitoring" permission or the user to disable system gestures.
        // LIMITATION: Public APIs cannot distinguish finger count on global scroll events.
        // This relies on the user disabling system gestures, which causes the system
        // to often fallback to sending scroll events for multi-finger swipes.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event, source: "Global")
        }
        
        // 2. Local Monitor (For when app/settings is focused/foreground)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event, source: "Local")
            return event
        }
    }
    
    private func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            self.globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            self.localMonitor = nil
        }
        logger.info("Stopped Gesture Monitoring")
    }
    
    private func handleScrollEvent(_ event: NSEvent, source: String) {
        // 1. Filter out vertical scrolls
        // If vertical delta is significant, user is likely scrolling a page, not switching spaces.
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            return
        }
        
        let now = Date().timeIntervalSince1970
        
        // 2. Reset Accumulator if time gap is too large (New Gesture)
        if now - lastEventTime > resetWindow {
            if currentDeltaX != 0 {
                logger.debug("Resetting accumulator (Gap: \(now - self.lastEventTime, format: .fixed(precision: 2))s)")
            }
            currentDeltaX = 0
        }
        lastEventTime = now
        
        // 3. Accumulate Delta
        // Global events often have phase==.none (0), so we rely on raw delta accumulation.
        currentDeltaX += event.scrollingDeltaX
        
        // Debug Output (Throttled log for significant movement)
        if abs(event.scrollingDeltaX) > 0.5 {
            logger.debug("[\(source)] dX: \(event.scrollingDeltaX, format: .fixed(precision: 1)) | Acc: \(self.currentDeltaX, format: .fixed(precision: 1))")
        }
        
        // 4. Check Threshold
        checkThreshold()
    }
    
    private func checkThreshold() {
        let now = Date().timeIntervalSince1970
        
        // Cooldown check (prevent double firing)
        guard now - lastSwitchTime > cooldown else { return }
        
        if abs(currentDeltaX) > swipeThreshold {
            // Determine direction
            // dX > 0: Typically "Swipe Left" (Content moves Right) in Natural Scrolling
            // dX < 0: Typically "Swipe Right" (Content moves Left) in Natural Scrolling
            let direction: SwipeDirection = currentDeltaX > 0 ? .left : .right
            
            logger.notice("TRIGGER: \(String(describing: direction)) | Acc: \(self.currentDeltaX)")
            print("GestureManager: Triggered \(direction)") // Console fallback
            
            triggerSwitch(direction: direction)
        }
    }
    
    enum SwipeDirection {
        case left
        case right
    }
    
    private func triggerSwitch(direction: SwipeDirection) {
        guard let sm = spaceManager else { return }
        
        lastSwitchTime = Date().timeIntervalSince1970
        currentDeltaX = 0
        
        DispatchQueue.main.async {
            // Logic Mapping (Fixed):
            // Direction based on standard macOS Mission Control behavior relative to Swipe.
            
            switch direction {
            case .left: // dX > 0 (Swipe Fingers Left)
                // User intention: "Move to the space on the left" (Previous) OR "Pull content right"
                // Fixed based on user feedback: Treat "Swipe Left" as going to PREVIOUS space.
                sm.switchToPreviousSpace()
                
            case .right: // dX < 0 (Swipe Fingers Right)
                // User intention: "Move to the space on the right" (Next)
                // Fixed based on user feedback: Treat "Swipe Right" as going to NEXT space.
                sm.switchToNextSpace()
            }
        }
    }
}
