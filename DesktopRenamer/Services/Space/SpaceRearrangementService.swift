import ApplicationServices
import AppKit
import CoreGraphics

/// Reorders Mission Control spaces through the Dock's Accessibility hierarchy.
/// macOS does not expose a public API for changing the order of spaces.
final class SpaceRearrangementService {
    static let shared = SpaceRearrangementService()

    enum Result {
        case success
        case failure(String)
    }

    private let dockBundleIdentifier = "com.apple.dock"
    private let missionControlKeyCode: CGKeyCode = 126

    private init() {}

    func rearrange(
        sourceID: String,
        before targetID: String,
        orderedSpaceIDs: [String],
        completion: @escaping (Result) -> Void
    ) {
        guard sourceID != targetID,
              let sourceIndex = orderedSpaceIDs.firstIndex(of: sourceID),
              let targetIndex = orderedSpaceIDs.firstIndex(of: targetID) else {
            completion(.failure(String(localized: "Choose two different spaces.")))
            return
        }
        guard AXIsProcessTrusted() else {
            completion(.failure(String(localized: "Accessibility permission is required to rearrange spaces.")))
            return
        }

        let originalMouseLocation = NSEvent.mouseLocation
        openMissionControl()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            let result = self.dragSpace(
                sourceIndex: sourceIndex,
                targetIndex: targetIndex,
                spaceCount: orderedSpaceIDs.count
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.closeMissionControl()
                self.restoreMouse(to: originalMouseLocation)
                completion(result)
            }
        }
    }

    private func openMissionControl() {
        postKeyEvent(keyCode: missionControlKeyCode, keyDown: true)
        postKeyEvent(keyCode: missionControlKeyCode, keyDown: false)
    }

    private func closeMissionControl() {
        postKeyEvent(keyCode: 53, keyDown: true, flags: [])
        postKeyEvent(keyCode: 53, keyDown: false, flags: [])
    }

    private func postKeyEvent(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags = .maskControl) {
        guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        event.post(tap: .cgSessionEventTap)
    }

    private func dragSpace(sourceIndex: Int, targetIndex: Int, spaceCount: Int) -> Result {
        guard let dock = runningDockElement() else { return .failure(String(localized: "Mission Control is not available.")) }
        let frames = uniqueFrames(spaceThumbnailFrames(in: dock))
            .filter { $0.width >= 50 && $0.height >= 30 }
            .sorted { $0.minX < $1.minX }
        guard frames.count >= spaceCount else { return .failure(String(localized: "Could not identify all spaces in Mission Control.")) }

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

    private func runningDockElement() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleIdentifier).first else { return nil }
        return AXUIElementCreateApplication(dock.processIdentifier)
    }

    private func spaceThumbnailFrames(in root: AXUIElement) -> [CGRect] {
        var frames: [CGRect] = []
        collectFrames(from: root, depth: 0, into: &frames)
        return frames
    }

    private func collectFrames(from element: AXUIElement, depth: Int, into frames: inout [CGRect]) {
        guard depth < 8 else { return }
        if let frame = frame(of: element), isPotentialThumbnail(frame), isVisible(element), isThumbnailRole(element) {
            frames.append(frame)
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return }
        for child in children { collectFrames(from: child, depth: depth + 1, into: &frames) }
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

    private func isThumbnailRole(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String else { return false }
        return role == "AXButton" || role == "AXGroup" || role == "AXImage"
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
