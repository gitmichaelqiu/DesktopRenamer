import Foundation
import IOKit

// C callbacks originating from the low-level Multitouch driver.

let ioKitCallback: @convention(c) (UnsafeMutableRawPointer?, io_iterator_t) -> Void = {
    (refCon, iterator) in
    guard let refCon = refCon else { return }
    let manager = Unmanaged<GestureManager>.fromOpaque(refCon).takeUnretainedValue()
    manager.consumeIterator(iterator)
}

func mtCallback(
    device: MTDeviceRef, touchPointer: UnsafeMutableRawPointer, numFingers: Int32,
    timestamp: Double, frame: Int32
) {
    guard let manager = GestureManager.sharedManager else { return }

    let typedPointer = touchPointer.assumingMemoryBound(to: MTTouch.self)
    let buffer = UnsafeBufferPointer(start: typedPointer, count: Int(numFingers))
    let touches = Array(buffer)

    // Valid states: 1 (Hover/Range), 2 (Touching), 3 (Dragging), 4 (Lifting)
    let validTouches = touches.filter { $0.state > 0 && $0.state < 7 }

    if validTouches.count >= 3 {
        GestureManager.lastTrackpadSwipeTime = Date().timeIntervalSince1970
    }

    // Calculate count from valid array, ignore raw numFingers if it mismatches active states
    let activeCount = validTouches.count

    if activeCount > 0 {
        manager.handleTouches(touches: validTouches, numFingers: activeCount)
    } else {
        // Send 0 to force reset
        manager.handleTouches(touches: [], numFingers: 0)
    }
}

