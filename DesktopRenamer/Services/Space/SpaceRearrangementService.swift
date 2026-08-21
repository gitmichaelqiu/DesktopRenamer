import ApplicationServices
import AppKit
import Combine
import CoreGraphics
import Darwin

/// Reorders Mission Control spaces through the Dock's Accessibility hierarchy.
/// macOS does not expose a public API for changing the order of spaces.
final class SpaceRearrangementService: ObservableObject {
    static let shared = SpaceRearrangementService()

    @Published private(set) var debugStatus = "Idle"

    enum Result {
        case success
        case failure(String)
    }

    private let dockBundleIdentifier = "com.apple.dock"
    private static var coreDockHandle: UnsafeMutableRawPointer?

    private init() {}

    func setDebugStatus(_ status: String) {
        if Thread.isMainThread {
            debugStatus = status
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.debugStatus = status
            }
        }
    }

    func rearrange(
        sourceID: String,
        before targetID: String,
        orderedSpaceIDs: [String],
        displayID: String? = nil,
        completion: @escaping (Result) -> Void
    ) {
        guard sourceID != targetID,
              let sourceIndex = orderedSpaceIDs.firstIndex(of: sourceID),
              let targetIndex = orderedSpaceIDs.firstIndex(of: targetID) else {
            let result = Result.failure(String(localized: "Choose two different spaces."))
            setDebugStatus(status(for: result))
            completion(result)
            return
        }
        guard AXIsProcessTrusted() else {
            let result = Result.failure(String(localized: "Accessibility permission is required to rearrange spaces."))
            setDebugStatus(status(for: result))
            completion(result)
            return
        }

        setDebugStatus("Running UI automation…")
        guard openMissionControl() else {
            let result = Result.failure(String(localized: "CoreDock Mission Control control is unavailable on this macOS installation."))
            setDebugStatus(status(for: result))
            completion(result)
            return
        }
        let originalMouseLocation = NSEvent.mouseLocation
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            let result = DispatchQueue.main.sync {
                self.dragSpaceWithRetry(
                    sourceIndex: sourceIndex,
                    targetIndex: targetIndex,
                    spaceCount: orderedSpaceIDs.count,
                    displayID: displayID
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.closeMissionControl()
                self.restoreMouse(to: originalMouseLocation)
                self.setDebugStatus(self.status(for: result))
                completion(result)
            }
        }
    }

    private func status(for result: Result) -> String {
        switch result {
        case .success:
            return "Debug rearrangement completed."
        case .failure(let error):
            return "Debug rearrangement failed: \(error)"
        }
    }

    private func openMissionControl() -> Bool {
        guard let dock = runningDockElement(), findElement(withIdentifier: "mc", in: dock) == nil else { return true }
        return postMissionControlNotification()
    }

    private func closeMissionControl() {
        guard let dock = runningDockElement(), findElement(withIdentifier: "mc", in: dock) != nil else { return }
        postMissionControlNotification()
    }

    @discardableResult
    private func postMissionControlNotification() -> Bool {
        // The Dock creates its Mission Control AX hierarchy after CoreDock receives
        // this notification. Keyboard shortcuts and distributed notifications are
        // user-configurable or ignored by newer macOS releases.
        typealias SendNotification = @convention(c) (CFString, Int32) -> Int32
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        if let symbol = dlsym(defaultHandle, "CoreDockSendNotification") {
            let send = unsafeBitCast(symbol, to: SendNotification.self)
            _ = send("com.apple.expose.awake" as CFString, 0)
            return true
        }

        if Self.coreDockHandle == nil {
            Self.coreDockHandle = dlopen(
                "/System/Library/PrivateFrameworks/CoreDock.framework/CoreDock",
                RTLD_LAZY
            )
        }
        guard let handle = Self.coreDockHandle,
              let symbol = dlsym(handle, "CoreDockSendNotification") else { return false }
        let send = unsafeBitCast(symbol, to: SendNotification.self)
        _ = send("com.apple.expose.awake" as CFString, 0)
        return true
    }

    private func dragSpace(sourceIndex: Int, targetIndex: Int, spaceCount: Int, displayID: String?) -> Result {
        guard let dock = runningDockElement() else { return .failure(String(localized: "Mission Control is not available.")) }
        let frames = missionControlSpaceFrames(in: dock, displayID: displayID)
        guard frames.count >= spaceCount else {
            return .failure(String(localized: "Could not identify all spaces in Mission Control (found \(frames.count) of \(spaceCount))."))
        }

        let sourceFrame = frames[sourceIndex]
        let targetFrame = frames[targetIndex]
        let sourcePoint = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let targetPoint = CGPoint(x: targetFrame.minX + 4, y: targetFrame.midY)
        guard postMouseEvent(.mouseMoved, at: sourcePoint),
              postMouseEvent(.leftMouseDown, at: sourcePoint),
              pauseBeforeNextMouseEvent(),
              postMouseEvent(.leftMouseDragged, at: sourcePoint),
              pauseBeforeNextMouseEvent(),
              postMouseEvent(.leftMouseDragged, at: targetPoint),
              pauseBeforeNextMouseEvent(),
              postMouseEvent(.leftMouseUp, at: targetPoint) else {
            return .failure(String(localized: "Could not drag the selected space."))
        }
        return .success
    }

    private func dragSpaceWithRetry(sourceIndex: Int, targetIndex: Int, spaceCount: Int, displayID: String?) -> Result {
        var lastResult: Result = .failure(String(localized: "Could not identify all spaces in Mission Control (found 0 of \(spaceCount))."))
        for _ in 0..<20 {
            let result = dragSpace(
                sourceIndex: sourceIndex,
                targetIndex: targetIndex,
                spaceCount: spaceCount,
                displayID: displayID
            )
            switch result {
            case .success:
                return result
            case .failure(let message) where message.contains("Could not identify all spaces"):
                lastResult = result
                Thread.sleep(forTimeInterval: 0.1)
            case .failure:
                return result
            }
        }
        return lastResult
    }

    private func runningDockElement() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleIdentifier).first else { return nil }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 2.0)
        return element
    }

    private func spaceThumbnailFrames(in root: AXUIElement) -> [CGRect] {
        var frames: [CGRect] = []
        collectFrames(from: root, depth: 0, into: &frames)
        let candidates = uniqueFrames(frames).filter { $0.width >= 50 && $0.height >= 30 }
        let rows = Dictionary(grouping: candidates) { Int($0.midY / 40) }
        let row = rows.max {
            if $0.value.count != $1.value.count { return $0.value.count < $1.value.count }
            return $0.key > $1.key
        }?.value.sorted { $0.minX < $1.minX } ?? []
        return row.isEmpty ? dockWindowFrames() : row
    }

    private func missionControlSpaceFrames(in dock: AXUIElement, displayID: String?) -> [CGRect] {
        guard let missionControl = findElement(withIdentifier: "mc", in: dock),
              let display = matchingDisplay(in: missionControl, displayID: displayID),
              let spaces = findElement(withIdentifier: "mc.spaces", in: display),
              let spacesList = findElement(withIdentifier: "mc.spaces.list", in: spaces) else {
            return spaceThumbnailFrames(in: dock)
        }

        return children(of: spacesList)
            .compactMap { frame(of: $0) }
            .filter { $0.width >= 50 && $0.height >= 30 }
            .sorted { $0.minX < $1.minX }
    }

    private func matchingDisplay(in missionControl: AXUIElement, displayID: String?) -> AXUIElement? {
        let displays = children(of: missionControl).filter { identifier(of: $0) == "mc.display" }
        guard let displayID else { return displays.first }
        return displays.first { attributeString("AXDisplayID", of: $0) == displayID } ?? displays.first
    }

    private func findElement(withIdentifier identifier: String, in root: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 10 else { return nil }
        if self.identifier(of: root) == identifier { return root }
        for child in children(of: root) {
            if let match = findElement(withIdentifier: identifier, in: child, depth: depth + 1) {
                return match
            }
        }
        return nil
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }
        return children
    }

    private func identifier(of element: AXUIElement) -> String? {
        attributeString(kAXIdentifierAttribute as String, of: element)
    }

    private func attributeString(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func dockWindowFrames() -> [CGRect] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleIdentifier).first else { return [] }
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let candidates = windows.compactMap { window -> CGRect? in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == Int(dock.processIdentifier),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat else { return nil }
            let frame = CGRect(x: x, y: y, width: width, height: height)
            return isPotentialThumbnail(frame) ? frame : nil
        }
        let unique = uniqueFrames(candidates)
        let rows = Dictionary(grouping: unique) { Int($0.midY / 40) }
        return rows.max {
            if $0.value.count != $1.value.count { return $0.value.count < $1.value.count }
            return $0.key > $1.key
        }?.value.sorted { $0.minX < $1.minX } ?? []
    }

    private func collectFrames(from element: AXUIElement, depth: Int, into frames: inout [CGRect]) {
        guard depth < 8 else { return }
        if let frame = frame(of: element), isPotentialThumbnail(frame), isVisible(element) {
            frames.append(frame)
        }

        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children { collectFrames(from: child, depth: depth + 1, into: &frames) }
        }

        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let windows = windowsValue as? [AXUIElement] {
            for window in windows { collectFrames(from: window, depth: depth + 1, into: &frames) }
        }
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let position = positionValue as! AXValue
        let axSize = sizeValue as! AXValue
        guard
              AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(axSize, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func isVisible(_ element: AXUIElement) -> Bool {
        var hiddenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXHiddenAttribute as CFString, &hiddenValue) == .success else { return true }
        return (hiddenValue as? Bool) != true
    }

    private func isPotentialThumbnail(_ frame: CGRect) -> Bool {
        let aspectRatio = frame.width / max(frame.height, 1)
        return frame.width <= 500 && frame.height <= 350 && aspectRatio >= 1.2 && aspectRatio <= 4.5
    }

    private func uniqueFrames(_ frames: [CGRect]) -> [CGRect] {
        var result: [CGRect] = []
        for frame in frames where !result.contains(where: { abs($0.midX - frame.midX) < 2 && abs($0.midY - frame.midY) < 2 }) { result.append(frame) }
        return result
    }

    private func postMouseEvent(_ type: CGEventType, at point: CGPoint) -> Bool {
        guard let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return false }
        event.post(tap: .cgSessionEventTap)
        return true
    }

    private func pauseBeforeNextMouseEvent() -> Bool {
        Thread.sleep(forTimeInterval: 0.08)
        return true
    }

    private func restoreMouse(to point: CGPoint) { CGWarpMouseCursorPosition(point) }
}
